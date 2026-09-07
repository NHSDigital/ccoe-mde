<!-- vale off -->

# Contributing to ccoe-mde

## Feature Branches

All changes to the repository must be created on a feature branch and submitted for peer review as a pull request (PR) via GitHub.

Feature branch names should describe the purpose of the change. For example:

```text
feature/documentation-update
```

## Main Branch

You are not permitted to push directly to the remote `main` branch in GitHub.

Changes to `main` require approval recorded on the pull request. Required approvers are controlled by the [CODEOWNERS](.github/CODEOWNERS) file.

Merges should only take place when:

- The change is ready to be accepted.
- All CI workflows have completed successfully.
- Required reviewers have approved the pull request.

## Coding Standards

Pull requests must follow the coding standards agreed for the project. Keep changes focused and update the documentation when behaviour or deployment steps change.

### Git Hooks

The repository includes a Gitleaks hook to help maintain standards and protect against secrets disclosure. Configure and run the hook before pushing changes to the remote repository. See the secret-scanning guidance in [README.md](README.md#secret-scanning).

## Testing Your Branch

Run the relevant tests and validation checks locally before raising or updating a pull request. At a minimum, scan the complete Git history for hard-coded secrets:

```shell
ALL_FILES=true ./scripts/githooks/scan-secrets.sh
```

## Documentation

When making changes to the Azure Function App, update [README.md](README.md) and any relevant function-level documentation so that deployment instructions and integration details remain current.

<!-- vale on -->
