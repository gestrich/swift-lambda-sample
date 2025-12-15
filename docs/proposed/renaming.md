# SDK Service → Client Renaming

Rename all `*Service` types in the `sdk-*` packages to `*Client`.

## Types to Rename

### sdk-cli

- [x] `CLIService` → `CLIClient` (Sources/sdk-cli/CLIClient.swift)
- [x] `CLIServiceError` → `CLIClientError` (Sources/sdk-cli/CLIClientError.swift)

### sdk-aws

- [ ] `AWSVaultService` → `AWSVaultClient` (Sources/sdk-aws/Auth/AWSVaultService.swift)
- [ ] `CloudFormationService` → `CloudFormationClient` (Sources/sdk-aws/CloudFormation/CloudFormationService.swift)
- [ ] `CDKService` → `CDKClient` (Sources/sdk-aws/Services/CDKService.swift)
- [ ] `CloudWatchLogsService` → `CloudWatchLogsClient` (Sources/sdk-aws/CloudWatch/CloudWatchLogsService.swift)

## Variable/Parameter Renames

- [ ] `cliService` → `cliClient` (throughout codebase)
- [ ] `vaultService` → `vaultClient` (in AWSCredentialProvider.swift)

## Files Outside sdk-* That Reference These Types

- Sources/service-deploy/* (multiple files)
- Sources/feature-mac/* (multiple files)
- Tests/sdk-cli-tests/*
- Tests/service-deploy-tests/*
