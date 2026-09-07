# Security

We take security and the protection of private data extremely seriously. This repository contains an Azure Function App proof of concept that accesses Microsoft Defender for Endpoint data and exports alerts to a receiving tenant. Changes must therefore be reviewed with particular care for credential handling, tenant isolation, and access permissions.

## Table of contents

- [Security](#security)
  - [Table of contents](#table-of-contents)
  - [Code update hygiene](#code-update-hygiene)
  - [Credential and secret handling](#credential-and-secret-handling)
  - [Privileged access mitigations](#privileged-access-mitigations)
  - [Reporting a vulnerability](#reporting-a-vulnerability)
  - [General security enquiries](#general-security-enquiries)

## Code update hygiene

The following controls help protect the integrity of changes to this repository:

* Changes should be made through pull requests and reviewed before they are merged.
* The repository's [CODEOWNERS](.github/CODEOWNERS) file identifies the code owners responsible for reviewing proposed changes.
* The [Gitleaks workflow](.github/workflows/scan-secrets.yml) scans pushes and pull requests for hard-coded secrets, including the repository history.
* Signed Git commits are required where branch protection rules enforce them. Commit signing helps prevent impersonation after authentication; see the [commit-signing guidance](https://github.com/NHSDigital/software-engineering-quality-framework/blob/main/practices/guides/commit-signing.md).

## Credential and secret handling

Credentials and other sensitive values must not be committed to this repository. In particular:

* Do not commit Azure Function local settings, `.env` files, certificates, private keys, access keys, refresh tokens, or connection strings.
* Runtime configuration and secrets must be supplied through protected Azure Function App settings or another approved secret-management mechanism.
* The deployment script retrieves service and workspace secrets at deployment time; these values must not be replaced with hard-coded values in the script.
* The application reads sensitive values from environment variables, including storage connection strings, Log Analytics keys, and Event Hub access keys. These values must never be written to source code, logs, documentation, or sample data.
* The repository's [`.gitignore`](.gitignore) excludes common local secret files, and Gitleaks findings must be investigated rather than broadly ignored.

## Privileged access mitigations

Changes that affect Azure authentication, Microsoft Defender for Endpoint access, deployment, or data export should follow these principles:

* Apply least privilege to service principals, users, Azure roles, and Microsoft Defender for Endpoint permissions.
* Scope access to the required tenant, subscription, resource group, device group, and data destination.
* Use read-only access for validation and investigation wherever write access is not required.
* Review changes to authentication and deployment code through the repository's pull-request and code-owner process.
* Do not expose OAuth access tokens, refresh tokens, storage keys, Log Analytics keys, or Event Hub keys in application logs or error messages.

## Reporting a vulnerability

If you believe you have found a security issue in this repository, please report it using GitHub's private vulnerability reporting:

1. [Report a vulnerability](https://github.com/NHSDigital/ccoe-mde/security/advisories/new)
2. Provide details of the issue and steps to reproduce

This creates a private channel for discussion and allows us to coordinate a fix before any public disclosure.

## General security enquiries

If you have general enquiries regarding our cybersecurity, please reach out to us at [cybersecurity@nhs.net](mailto:cybersecurity@nhs.net).
