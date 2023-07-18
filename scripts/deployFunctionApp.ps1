## To deploy the MDE Function App, replace the Variable values in the block below and run the script from a PowerShell terminal with the 'scripts' folder as the current directory
## You will be asked to sign into the relevant Azure tenant as part of the script.
## The script expects a target Log Analytics Workspace to already exist, with or without Sentinel deployed into it, and optionally an Event Hub if that is the desired output for the Alert data

## Variables
$tenantId = "<Add Tenant Id>" # Tenant ID where the resources will be deployed
$subscriptionId = "<Add Subscription Id>" # Subscription ID where the resources will be deployed
$FunctionConfigMDETenantId = "<Add MDE Tenant ID>" # MDE Tenant ID
$FunctionConfigMDEClientAppId = "<Add MDE Client ID>" # MDE SPN Client ID

# Alert Target Type can be set to either LogAnalytics or EventHub
$FunctionConfigAlertTargetType = "LogAnalytics" # Set this to either LogAnalytics or EventHub - these targets must exist in the same tenant as the function app and be present before this script is run
$AlertTargetResourceGroupName = "<Add Resource Group name>" # Add Resource Group name where the target Log Analytics Workspace or Event Hub reside in your local tenant
$LogAnalyticsWorkspaceName = "<Add Log analytics workspace name>" # Log Analytics Workspace name used to look up workspace id and key if workspace is to be used as the alert target or for sending Heartbeat events to

$FunctionConfigEventHubNamespace = "<Add Event Hub Namespace name>" # Add Event Hub Namespace name if Alert Target is Event Hub, otherwise leave blank
$FunctionConfigEventHubName = "<Add Event Hub name>" # Add Event Hub name if Alert Target is Event Hub, otherwise leave blank
$FunctionConfigEventHubAccessKeyName = "RootManageSharedAccessKey" # Add Event Hub Access Key Name - can be namespace root or hub-specific

# Remaining variables can be left as default unless there are specific reasons to change them
$randomIdentifier = Get-Random -Maximum 9999
$location = "uksouth"
$functionAppResourceGroup = "azure-functions-rg-$randomIdentifier"
$tag = @{application = "function-app-consumption-python" }
$storage = "funcappsaccount$randomIdentifier"
$functionApp = "serverless-python-function-$randomIdentifier"
$skuStorage = "Standard_LRS"
$functionsVersion = "4"
$pythonVersion = "3.9" 
$FunctionConfigSendHeartbeatToLogAnalytics = "True"
$FunctionConfigUse_last_saved_time = "True"
$FunctionConfigLogAnalyticsTableName = "DefenderRawAlert"
$FunctionConfigStorageTable = "fnautomationmdeCachedValues"
$FunctionConfigStorageContainer = "functionlogging"
$FunctionConfigLoggingLevel = "4" # Set this to value in range 1-5 where 1 logs everything and 5 logs only most significant output
$filepath = "Python-Functions.zip"

## Determine if uswr needs to be prompted to refresh their Azure login
$Prompt = "Do you need to refresh your Azure login before running the script (No, if already correctly logged in or if running in Cloud Shell)?"
$Choices = [System.Management.Automation.Host.ChoiceDescription[]] @("&Yes", "&No", "&Cancel")
$Default = 1

# Prompt for the choice
$Choice = $host.UI.PromptForChoice('', $Prompt, $Choices, $Default)

# Action based on the choice
switch ($Choice) {
    0 { 
        # Sign in to azure after signing out of any current sessions if required
        If (Get-AzContext) { Disconnect-AzAccount }
        Connect-AzAccount -Tenant $tenantId -Subscription $subscriptionId
    }
    1 { Write-Host "Using existing Azure login" }
    2 { exit 1 }
}

# Suppress AZ module warning messages
Update-AzConfig -DisplayBreakingChangeWarning $false
$ConfirmPreference = 'None'

## Check if az modules are installed and install if needed ##
Write-Output "Checking for required modules"
if (!(Get-Module -Name Az -ListAvailable)) {
    Write-Output "Module not installed, Installing required modules ..."
    Install-Module -Name Az -AllowClobber -Scope CurrentUser    
}
else {
    Write-Output "Required modules installed"
}

## Compress python functions files
try {
    $compress = @{
        Path             = "..\python\*"
        CompressionLevel = "Fastest"
        DestinationPath  = "$filepath"
    }
    Write-Output "Compressing python functions files"
    Compress-Archive @compress -Force
}
catch {
    Write-Error "Error compressing files: $_"
    exit 1
}

## Check that the "Microsoft.Web" resource provider is deployed within the tenant. 
## This is needed for the tenant to be able to host a variety of web applications.
# Set the resource provider name
$resourceProviderName = "Microsoft.Web"
# Check if the resource provider is already enabled
$resourceProvider = Get-AzResourceProvider -ProviderNamespace $resourceProviderName
if ($resourceProvider.RegistrationState[0] -eq "Registered") {
    Write-Output "The resource provider is already enabled."
}
else {
    # Enable the resource provider
    Write-Output "Enabling the resource provider required for the function app..."
    Register-AzResourceProvider -ProviderNamespace $resourceProviderName

    # Wait for the resource provider to be enabled
    Write-Output "Waiting for the resource provider $($resourceProviderName) to be enabled, this may take few minutes..."
    do {
        Start-Sleep -Seconds 10
        $resourceProvider = Get-AzResourceProvider -ProviderNamespace $resourceProviderName
        Write-Output "Current status: $($resourceProvider.RegistrationState[0])"
    } until ($resourceProvider.RegistrationState -eq "Registered")

    # The resource provider is now enabled
    Write-Output "The resource provider $($resourceProviderName) is now enabled."
}

## Get Log Analytics Workspace Key and Id
## Can be hard coded if in a different tenant or user login used to run this script does not have access to these details
$FunctionConfigLogAnalyticsKeyValue = "" # Value will be read from the environment
$FunctionConfigEventHubAccessKeyValue = "" # Value will be read from the environment
if (Get-AzResourceGroup -Name $AlertTargetResourceGroupName -ErrorAction SilentlyContinue) {
    # If a Log Analytics workspace name has been specified, look up the key for it:
    if ($LogAnalyticsWorkspaceName.Length -gt 0) {
        $FunctionConfigLogAnalyticsKeyValue = "$($(Get-AzOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $AlertTargetResourceGroupName -Name $LogAnalyticsWorkspaceName).PrimarySharedKey)"# Log Analytics Primary key
        $FunctionConfigLogAnalyticsWorkspaceId = "$($(Get-AzOperationalInsightsWorkspace -ResourceGroupName $AlertTargetResourceGroupName -Name $LogAnalyticsWorkspaceName).CustomerId)" # LAW ID to ingest the alerts

        # Check workspace details were read successfully
        if ($FunctionConfigLogAnalyticsKeyValue.length -eq 0) {
            Write-Error "The Log Analytics Workspace Key could not be read"
            exit 1
        }
        
        if ($FunctionConfigLogAnalyticsWorkspaceId.length -eq 0) {
            Write-Error "The Log Analytics Workspace ID could not be read"
            exit 1
        }
    }

    # If an Event Hub name has been specified, look up the access key for it:
    if ($FunctionConfigEventHubName.Length -gt 0) {
        $FunctionConfigEventHubAccessKeyValue = "$($(Get-AzEventHubKey -ResourceGroupName $AlertTargetResourceGroupName -NamespaceName $FunctionConfigEventHubNamespace -EventHubName $FunctionConfigEventHubName -Name $FunctionConfigEventHubAccessKeyName -ErrorAction SilentlyContinue).PrimaryKey)" # Event Hub Primary key

        # Check Event Hub details were read successfully and try reading from namespace level if not
        if ($FunctionConfigEventHubAccessKeyValue.length -eq 0) {
            Write-Information "The Event Hub Access Key Value could not be read - try reading Event Hub Namespace Access Key Value instead"
            $FunctionConfigEventHubAccessKeyValue = "$($(Get-AzEventHubKey -ResourceGroupName $AlertTargetResourceGroupName -NamespaceName $FunctionConfigEventHubNamespace -Name $FunctionConfigEventHubAccessKeyName -ErrorAction SilentlyContinue).PrimaryKey)"
            
            if ($FunctionConfigEventHubAccessKeyValue.length -eq 0) {
                Write-Error "The Event Hub Namespace Access Key Value could not be read"
                exit 1
            }
            else {
                Write-Information "The Event Hub Namespace Access Key Value was read successfully"
                $FunctionConfigEventHubAccessKeyType = "Namespace"
            }
        }
        else {
            Write-Information "The Event Hub Access Key Value was read successfully"
            $FunctionConfigEventHubAccessKeyType = "EventHub"
        }
    }
}
else {
    Write-Error "The Log Analytics resource group does not exist: $AlertTargetResourceGroupName"
    exit 1
}


## Create azure resources ##
# Create a resource group
Write-Output "Creating Resource Group: $functionAppResourceGroup in $location..."

try {
    New-AzResourceGroup `
        -Name $functionAppResourceGroup `
        -Location $location `
        -Tag $tag
    Write-Output "Resource Group $functionAppResourceGroup was created successfully."
}
catch {
    Write-Error "Error creating Resource Group $functionAppResourceGroup : $_"
    exit 1
}

# Create an Azure storage account in the resource group.
# Check if the storage account already exists
if (Get-AzStorageAccount -Name $storage -ResourceGroupName $functionAppResourceGroup -ErrorAction SilentlyContinue) {
    Write-Output "A storage account with name $storage already exists, please run the script again."
    return
}

# Create a new Azure Storage Account
Write-Output "Creating storage account: $storage..."

try {
    $storageAccount = New-AzStorageAccount `
        -Name $storage `
        -Location $location `
        -ResourceGroupName $functionAppResourceGroup `
        -SkuName $skuStorage `
        -Tag $tag
    Write-Output "Storage account $storage was created successfully."
}
catch {
    Write-Error "Error creating storage account $storage : $_"
    exit 1
}

# Create table
Write-Output "Creating table: $FunctionConfigStorageTable in the storage account: $storage"
$ctx = $storageAccount.Context
try {
    New-AzStorageTable `
        -Name $FunctionConfigStorageTable `
        -Context $ctx
    Write-Output "Storage table $FunctionConfigStorageTable was created successfully."
}
catch {
    Write-Error "Error creating storage table $FunctionConfigStorageTable : $_"
    exit 1
}

# Create a serverless Python function app in the resource group.
Write-Output "Creating Function App: $functionApp"
try {
    New-AzFunctionApp `
        -Name $functionApp `
        -StorageAccountName $storage `
        -Location $location `
        -ResourceGroupName $functionAppResourceGroup `
        -OSType Linux `
        -Runtime Python `
        -RuntimeVersion $pythonVersion `
        -FunctionsVersion $functionsVersion `
        -IdentityType SystemAssigned `
        -Tag $tag
    Write-Output "Function App $functionApp was created successfully."
}
catch {
    Write-Error "Error creating Function App $functionApp : $_"
    exit 1
}

## Publish the app to the function
# upload the function .zip file to the function app
Write-Output "Uploading functions to $functionApp"
try {
    Publish-AzWebapp `
        -ResourceGroupName $functionAppResourceGroup `
        -Name $functionApp `
        -ArchivePath $filepath `
        -Force `
        -ErrorAction Stop
    Write-Output "Functions were uploaded successfully to $functionApp."
}
catch {
    Write-Error "Error uploading functions to $functionApp : $_"
    exit 1
}

# Add application settings to the function app
$appSettings = @{
    "FunctionConfigSendHeartbeatToLogAnalytics" = "$FunctionConfigSendHeartbeatToLogAnalytics"
    "FunctionConfigUse_last_saved_time"         = "$FunctionConfigUse_last_saved_time"
    "FunctionConfigAlertTargetType"             = "$FunctionConfigAlertTargetType"
    "FunctionConfigLogAnalyticsKeyValue"        = "$FunctionConfigLogAnalyticsKeyValue"
    "FunctionConfigLogAnalyticsWorkspaceId"     = "$FunctionConfigLogAnalyticsWorkspaceId"
    "FunctionConfigLogAnalyticsTableName"       = "$FunctionConfigLogAnalyticsTableName"
    "FunctionConfigEventHubNamespace"           = "$FunctionConfigEventHubNamespace"
    "FunctionConfigEventHubName"                = "$FunctionConfigEventHubName"
    "FunctionConfigEventHubAccessKeyName"       = "$FunctionConfigEventHubAccessKeyName"
    "FunctionConfigEventHubAccessKeyValue"      = "$FunctionConfigEventHubAccessKeyValue"
    "FunctionConfigEventHubAccessKeyType"       = "$FunctionConfigEventHubAccessKeyType"
    "FunctionConfigMDETenantId"                 = "$FunctionConfigMDETenantId"
    "FunctionConfigMDEClientAppId"              = "$FunctionConfigMDEClientAppId"
    "FunctionConfigStorageTable"                = "$FunctionConfigStorageTable"
    "FunctionConfigStorageContainer"            = "$FunctionConfigStorageContainer"
    "FunctionConfigQueryDepth"                  = "2"
    "FunctionConfigLoggingType"                 = "logging"
    "FunctionConfigLoggingLevel"                = "$FunctionConfigLoggingLevel"
}

try {
    Update-AzFunctionAppSetting `
        -Name $functionApp `
        -ResourceGroupName $functionAppResourceGroup `
        -AppSetting $appSettings `
        -ErrorAction Stop
    Write-Output "Application settings were added to $functionApp."
}
catch {
    Write-Error "Error adding application settings to $functionApp : $_"
    exit 1
}

## delete zip file if exists
if (Test-Path $filepath) {
    try {
        Remove-Item $filepath -Force
        Write-Output "$filepath has been deleted"
    }
    catch {
        Write-Output "Error deleting $filepath : $($_.Exception.Message)"
    }
}
else {
    Write-Output "$filepath doesn't exist"
}


Write-Output "***************************************************************"
Write-Output "*           Azure Function app deployed successfully.         *"
Write-Output "*   Open the Function App in the Azure Portal to authenticate *"
Write-Output "***************************************************************"

