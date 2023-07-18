# Azure Function App Proof of Concept

## Overview of Solution

CCoE was asked to provide a solution that could be run in an Azure Function App to call the MDE Graph APIs to extract alert data from the central tenant, while meeting the data scoping requirement via an App Registration service principal with (user) Delegated Permissions.

With this access model, the service principal provides initial authorisation to access the APIs, but RBAC level control over data access is determined by the credentials of the user who actually authenticates the OAuth credential flow used by the API calls.

This results in a fairly simple architectural model being required and has the additional advantage that the majority of the resources involved are owned and managed by the external organisation, reducing the management and cost burden on the CSOC team.

## Table of Content

- [Introduction](#introduction)
- [High Level Design](#high-level-design)
  - [Identity Tenant Resources](#identity-tenant-resources)
  - [Trust Tenant](#trust-tenant)
    - [Storage Account Table](#storage-account-table)
    - [App Service Plan](#app-service-plan)
    - [Function App](#function-app)
    - [App Settings](#app-settings)
    - [Log Analytics Workspace](#log-analytics-workspace)
- [Deployment Guidelines](#deployment-guidelines)
  - [Prerequisites](#prerequisites)
  - [Deploy Code](#deploy-code)
  - [Installation Steps](#installation-steps)
- [Azure Function App Authentication](#azure-function-app-authentication)
- [Deployment Checklist](#deployment-checklist)
- [Future Roadmap](#future-roadmap)
- [Glossary of Terms](#glossary-of-terms)
- [Resources](#resources)

## Introduction

A centralised identity management team within NHSE CSOC is responsible for managing the Active Directory that devices across many distributed NHS organisations (e.g., Trusts) use to authenticate users and register end-user devices against.

Microsoft Defender for Endpoint (MDE) is enabled within the synchronised Azure Active Directory (AAD) tenant to detect security events originating within these devices.

The CCoE was asked to assist the security team in creating a process to allow the distributed organisations to extract Microsoft Defender for Endpoint Alerts from the central Identity Tenant into their own SIEM tooling.

The devices are segregated by organisation within MDE by the use of Device Groups, and a core tenant of the final solution was that the extracts MUST be scoped to just the alerts from devices in a specific group (i.e., the devices managed by the organisation querying the data), with no risk of data from the other organisations also being accessible.

## High Level Design

The solution is designed to export MDE Alerts from one tenant and push them to another. For simplicity’s sake these are referred to as the “Identity Tenant”, where MDE exists, and the “Trust Tenant”, where the Function App exists and probably, but not necessarily, where alerts will be pushed to.

![Solution Diagram](/images/Diagram.png)

### Identity Tenant Resources

On the assumption that the Identity Tenant already exists and that MDE is deployed into it with devices grouped by appropriate end-user Device Groups, very minimal change is required in the tenant to deploy this solution.
In fact, the only resource required is an App Registration service principal with relevant API permissions assigned to it:

![Service Principal Permissions](/images/SPN_Permissions.png)

## Trust Tenant

The bulk of the solution exists within the Trust Tenant and is comprised of the following resources, most of which are automatically created as part of the deployment process defined below.

### Storage Account Table

Required internally by the Function App to store session state information and also used to store the last successful query time.

### App Service Plan

Consumption plan is sufficient but does not allow creation of private endpoints, which means that public networking must be used to connect to the storage account.

As neither of the function app and the storage account contain sensitive data this does not introduce significant security risks, but it is recommended that a paid-for service plan is used so that private endpoints can be implemented if possible.

Having said this, the solution was developed and tested using a Linux Y1 consumption-based plan.

### Function App

The main functionality of the solution is provided by a Python 3.9 function with three component parts:

- `entity-Python-LogAnalytics`: manages entity state to provide stateful sessions to the timer function
- `orchestrator-Python-LogAnalytics`: orchestrates the workflow between the entity and timer functions
- `timer-Python-LogAnalytics`: contains the main function code that runs on a scheduled basis to perform the alert extracts.

> :heavy_exclamation_mark: Note that the function app and storage account do not contain sensitive data, so public networking is not a significant security risk. However, it is recommended to use a paid service plan to implement private endpoints if possible.

### App Settings

A number of App Settings are used in the function app to store run-time variables, such as tenant and client Ids, the storage account name etc.

### Log Analytics Workspace

Used to store function logging data and, in default deployment, the alerts extracted from MDE. This must be created in advance of running the deployment and can be a pre-existing workspace.

## Deployment Guidelines

### Prerequisites

1. Register **Microsoft.Web** resource provider, see: [Register resource provider](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-providers-and-types#azure-portal)

> :heavy_exclamation_mark: Note: It may be necessary to wait between 20 minutes and 12 hours for the registration to complete. See linked documentation for how to review this progress.

2. Azure User with Owner or Contributor right to the subscription that the Function App will be deployed into.

### Deploy Code

The deployment can be built using a PowerShell script available in this repo.
The following variables relating to the Identity and Trust tenant environments need to be set in the PowerShell code:

| Variable name | Description                           |
|---------------------|-----------------------------------------------|
|$tenantId | Add the Tenant ID where the resources will be deployed |
|$subscriptionId | Add the Subscription ID where the resources will be deployed|
|$FunctionConfigMDETenantId  |Add MDE Tenant ID|
|$FunctionConfigMDEClientAppId | Add MDE Client ID |
|$LogAnalyticsWorkspaceResourceGroupName| Add the Log analytics Workspace Resource Group name|
|$LogAnalyticsWorkspaceName |Add the Log analytics Workspace name|
|$FunctionConfigLogAnalyticsKey |Holds the Log analytics primary key|
|$FunctionConfigLogAnalyticsWorkspaceId |Holds the Log analytics Id|
|$randomIdentifier |  Get-Random|
|$location  | "uksouth"|
|$resourceGroup  | "azure-functions-rg-$randomIdentifier"|
|$tag |  @{application  "function-app-consumption-python" }|
|$storage |  "funcappsaccount$randomIdentifier"|
|$functionApp  | "serverless-python-function-$randomIdentifier"|
|$skuStorage  | "Standard_LRS"|
|$functionsVersion  | "4"|
|$pythonVersion  | "3.9" #Allowed values: 3.7, 3.8, and 3.9|
|$FunctionConfigSend_heartbeat   | "True"|
|$FunctionConfigUse_last_saved_time |  "True"|
|$FunctionConfigLogAnalyticsTableName  | "DefenderRawAlert"|
|$FunctionConfigStorageTable |  "fnautomationmdeCachedValues"|
|$FunctionConfigStorageContainer |  "functionlogging"|
|$filepath|   "Python-Functions.zip"|

### Installation Steps

1. Clone the repo to your local machine or Azure Cloud Shell by running the following command:

```shell
git clone https://github.com/NHSDigital/ccoe-mde.git
```

2. Edit the variables in the file **deployFunctionApp.ps1** located inside the scripts folder, using your preferred text editor, according to your Azure environment. The variables to edit are:

| Variable | Description |
| :------- | :---------- |
| $tenantId | Tenant ID where the resources will be deployed |
| $subscriptionId | Subscription ID where the resources will be deployed |
| $FunctionConfigMDETenantId | MDE Tenant ID |
| $FunctionConfigMDEClientAppId | MDE Client ID |
| $LogAnalyticsWorkspaceResourceGroupName | Log analytics Resource Group name |
| $LogAnalyticsWorkspaceName | Log analytics Workspace name |

3. Once edited, open PowerShell and navigate to the **scripts** folder inside the cloned repo and Run the script.

```shell
  .\deployFunctionApp.ps1
```

4. A browser window will pop up requesting authentication into Azure Portal to start the deployment of the required resources.

![Azure Portal Authentication](/images/AzurePortalAuthentication.png)

5. Wait for the deployment process to complete.

![Sucessful installation](/images/SucessfulInstallation.png)

## Azure Function App Authentication

1. Go to the *Azure* portal and search for Function App, click on the function that just deployed (serverless-python-function-xxxxxxxxx).

![Azure Portal Search Azure Function App](/images/AzurePortalSearch.png)

2. In the Function App's overview page, click on the **Functions** in the Functions section on the left-hand side.

![Azure Portal Azure Function App Menu](/images/AzureFunctionAppMenu.png)

3. Select the Timer function named **"timer_Python_LogAnalytics"**.

![Azure Portal Azure Function App Fuctions](/images/AzureFunctionAppFunctions.png)

4. Click on the **Monitor** in the Developer section.

![Azure Portal Azure Function App Monitor](/images/AzureFunctionAppMonitor.png)

5. Click on **Logs** and wait for the logs to update (it might take a few minutes).

![Azure Portal Azure Function App Log](/images/AzureFunctionAppMonitorLog.png)

6. To authenticate the Azure Function, click on the following URL <https://microsoft.com/devicelogin> add the code shown in the **logs** and log in using a user credential that has RBAC permission in the MDE environment.

![Azure Portal Azure Function Authentication](/images/AzureFunctionAppAuthentication.png)

## Deployment Checklist

| Task                                                                                   | Completed |
|----------------------------------------------------------------------------------------|-----------|
| Register **Microsoft.Web** resource provider.                                              | <a href="#" onclick="toggleCheckbox('task1');return false;"><input type="checkbox" id="task1" name="task1" value="value1"></a> |
| Ensure Azure User has **Contributor** or **Owner** rights to subscription.                     | <a href="#" onclick="toggleCheckbox('task2');return false;"><input type="checkbox" id="task2" name="task2" value="value2"></a> |
| Clone the repo.                                                                         | <a href="#" onclick="toggleCheckbox('task3');return false;"><input type="checkbox" id="task3" name="task3" value="value3"></a> |
| Edit the variables Tenant ID, Subscription ID, MDE Tenant ID, MDE Client ID, Log Analytics workspace name, and Log Analytics Resource Group name. | <a href="#" onclick="toggleCheckbox('task4');return false;"><input type="checkbox" id="task4" name="task4" value="value4"></a> |
| Authenticate the Azure Function using the device code shown on the function app logs. | <a href="#" onclick="toggleCheckbox('task5');return false;"><input type="checkbox" id="task5" name="task5" value="value5"></a> |
| After 30 minutes check if the new tables **DefenderRawAlert_CL** and **Heartbeat_CL** were created in the specified Log Analytics Workspace. | <a href="#" onclick="toggleCheckbox('task6');return false;"><input type="checkbox" id="task6" name="task6" value="value6"></a> |

## Future Roadmap

- Amend Deployment Script to allow Python code to be redeployed into existing Function App.

- Create Action Group to alert when Heartbeat is not received.

- Create Sentinel Alert Rules that convert raw alert data into Sentinel Alerts to the deployment  script.

- Use Managed Identity to access Storage Account.

- Add alternative Alert output formats and locations (e.g. Storage Account, Event Hub, AWS S3 bucket etc).

## Glossary of Terms

| Term / Abbreviation | What it stands for                            |
|---------------------|-----------------------------------------------|
| API                 | Application Programming Interface             |
| CASB                | Cloud Access Security Broker                  |
| CSOC                | Cyber Security Operations Centre              |
| CSPM                | Cloud Security Posture Management             |
| CWPP                | Cloud Workload Protection Platform            |
| EDR                 | Endpoint Detection and Response               |
| MDC                 | Microsoft Defender for Cloud                  |
| MDE                 | Microsoft Defender for Endpoint               |
| SIEM                | Security Information and Event Management     |
| SOAR                | Security Orchestration, Automation and Response |
| TI / TIP            | Threat Intelligence / Threat Intelligence Platform |
| UEBA                | User and Entity Behaviour Analytics           |
| RBAC                | Role-based access control                     |

## Resources

- [Microsoft Graph API - Security List Alerts v2](https://learn.microsoft.com/en-us/graph/api/security-list-alerts_v2?view=graph-rest-1.0&tabs=http)
- [Azure Durable Functions Overview](https://learn.microsoft.com/en-us/azure/azure-functions/durable/durable-functions-overview?tabs=csharp-inproc)
- [Microsoft Authentication Library (MSAL) Overview](https://learn.microsoft.com/en-us/azure/active-directory/develop/msal-overview)
- [Microsoft Authentication Library (MSAL) for Desktop Apps with Device Code Flow](https://learn.microsoft.com/en-us/azure/active-directory/develop/scenario-desktop-acquire-token-device-code-flow?tabs=python)
