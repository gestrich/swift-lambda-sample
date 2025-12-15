# SDK Service → Client Renaming

Rename all `*Service` types in the `sdk-*` packages to `*Client`.

## Types to Rename

### sdk-cli

- [x] `CLIService` → `CLIClient` (Sources/sdk-cli/CLIClient.swift)
- [x] `CLIServiceError` → `CLIClientError` (Sources/sdk-cli/CLIClientError.swift)

### sdk-aws

- [x] `AWSVaultService` → `AWSVaultClient` (Sources/sdk-aws/Auth/AWSVaultClient.swift)
- [x] `CloudFormationService` → `CloudFormationClient` (Sources/sdk-aws/CloudFormation/CloudFormationClient.swift)
- [x] `CDKService` → `CDKClient` (Sources/sdk-aws/Services/CDKClient.swift)
- [x] `CloudWatchLogsService` → `CloudWatchLogsClient` (Sources/sdk-aws/CloudWatch/CloudWatchLogsClient.swift)

## Variable/Parameter Renames

- [ ] `cliService` → `cliClient` (throughout codebase)
- [x] `vaultService` → `vaultClient` (in AWSCredentialProvider.swift, AWSCLIService.swift, LambdaBuildService.swift)

## Files Outside sdk-* That Reference These Types

- Sources/service-deploy/* (multiple files)
- Sources/feature-mac/* (multiple files)
- Tests/sdk-cli-tests/*
- Tests/service-deploy-tests/*
