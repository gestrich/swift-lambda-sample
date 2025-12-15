    # SwiftDeploy Folder Organization Proposal

This document proposes a service-based reorganization of the SwiftDeploy sources, where each top-level folder could eventually become its own Swift module.

## Current Issues

1. **Inconsistent folder naming**: `AWSLocalServices/` vs `CLIServices/` vs `Services/`
2. **Mixed concerns**: `BuildState.swift` contains error, status enum, and state struct
3. **Scattered top-level files**: Configuration types mixed at root level
4. **Generic naming**: `Services/` folder is too broad

## Proposed Structure: Service-Based Modules

```
SwiftDeploy/
│
├── Core/                             # Shared foundation (could stay in main module)
│   ├── Errors/
│   │   └── DeployError.swift
│   └── DependencyCheckerService.swift
│
├── GitHubService/                    # GitHub CI/CD integration
│   ├── GitHubConfiguration.swift
│   ├── GitHubActionsService.swift
│   ├── GitHubCLIService.swift
│   ├── GitService.swift              # Git operations (could be separate)
│   ├── Models/
│   │   └── GitStatus.swift           # (if exists as separate type)
│   └── CLI/
│       └── Gh.swift                  # GitHub CLI program definition
│
├── AWSService/                       # AWS CLI operations
│   ├── AWSAuthConfiguration.swift
│   ├── AWSCLIService.swift
│   ├── AWSVaultService.swift
│   ├── AWSTestingService.swift
│   └── CLI/
│       └── Aws.swift                 # AWS CLI program definition
│
├── CDKService/                       # CDK/CloudFormation infrastructure
│   ├── CDKService.swift
│   ├── CDKInfrastructureQueryService.swift
│   ├── CDKOutputParser.swift
│   ├── Models/
│   │   ├── CDKStackConfiguration.swift
│   │   ├── CDKStackOutputs.swift
│   │   ├── CDKInfrastructureStatus.swift
│   │   ├── CDKInfrastructureConfiguration.swift
│   │   ├── CDKDeploymentProgress.swift
│   │   ├── CloudFormationStackStatus.swift
│   │   └── DeploymentConfiguration.swift    # renamed from DeploymentOptions
│   ├── Errors/
│   │   └── CDKInfrastructureError.swift
│   └── CLI/
│       ├── Cdk.swift
│       └── Npm.swift
│
├── DockerService/                    # Docker container management
│   ├── DockerService.swift
│   └── CLI/
│       └── Docker.swift
│
├── LambdaService/                    # Lambda build & lifecycle
│   ├── Protocols/
│   │   └── LambdaService.swift       # Protocol for all Lambda services
│   ├── LambdaBuildService.swift
│   ├── Models/
│   │   ├── BuildState.swift
│   │   ├── BuildStatus.swift         # extract from BuildState
│   │   └── LambdaState.swift         # (if exists)
│   ├── Errors/
│   │   └── BuildError.swift          # extract from BuildState
│   └── CLI/
│       ├── SwiftCLI.swift
│       └── BuildScript.swift
│
├── LocalDevelopmentService/          # Local dev environment (Docker-based)
│   ├── Protocols/
│   │   └── LocalService.swift
│   ├── XcodeLocalDevelopmentService.swift
│   ├── LinuxLocalDevelopmentService.swift
│   ├── Containers/                   # Individual container services
│   │   ├── PostgreSQLLocalService.swift
│   │   ├── MinIOService.swift
│   │   └── DynamoDBLocalService.swift
│   └── EnvironmentVariables.swift    # fix typo from current EnviromentVariables
│
├── RemoteDeploymentService/          # Remote AWS deployment orchestration
│   └── RemoteDeploymentService.swift
│
└── ToolsService/                     # Misc tooling (Homebrew, Node, etc.)
    └── CLI/
        ├── Brew.swift
        ├── Homebrew.swift
        └── Node.swift
```

## Module Dependencies (Future)

When modularized, the dependency graph would look like:

```
┌─────────────────────────────────────────────────────────┐
│                  RemoteDeploymentService                │
│    (orchestrates full deployments)                      │
└─────────────────────────────────────────────────────────┘
         │              │              │
         ▼              ▼              ▼
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│ CDKService  │  │GitHubService│  │ AWSService  │
└─────────────┘  └─────────────┘  └─────────────┘
         │              │
         ▼              ▼
┌─────────────────────────────────────────────────────────┐
│              LocalDevelopmentService                    │
└─────────────────────────────────────────────────────────┘
         │              │
         ▼              ▼
┌─────────────┐  ┌──────────────┐
│DockerService│  │LambdaService │
└─────────────┘  └──────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────┐
│                    Core / CLIKit                        │
└─────────────────────────────────────────────────────────┘
```

## Migration Map

| Current Location | Proposed Location | Notes |
|------------------|-------------------|-------|
| `CLIPrograms/Aws.swift` | `AWSService/CLI/Aws.swift` | CLI definitions live with their service |
| `CLIPrograms/Gh.swift` | `GitHubService/CLI/Gh.swift` | |
| `CLIPrograms/Docker.swift` | `DockerService/CLI/Docker.swift` | |
| `CLIPrograms/Cdk.swift` | `CDKService/CLI/Cdk.swift` | |
| `CLIPrograms/Npm.swift` | `CDKService/CLI/Npm.swift` | NPM used for CDK |
| `CLIPrograms/SwiftCLI.swift` | `LambdaService/CLI/SwiftCLI.swift` | |
| `CLIPrograms/BuildScript.swift` | `LambdaService/CLI/BuildScript.swift` | |
| `CLIPrograms/Brew.swift` | `ToolsService/CLI/Brew.swift` | |
| `CLIPrograms/Homebrew.swift` | `ToolsService/CLI/Homebrew.swift` | |
| `CLIPrograms/Node.swift` | `ToolsService/CLI/Node.swift` | |
| `CLIServices/AWSCLIService.swift` | `AWSService/AWSCLIService.swift` | |
| `CLIServices/AWSVaultService.swift` | `AWSService/AWSVaultService.swift` | |
| `CLIServices/CDKService.swift` | `CDKService/CDKService.swift` | |
| `CLIServices/DockerService.swift` | `DockerService/DockerService.swift` | |
| `CLIServices/GitHubCLIService.swift` | `GitHubService/GitHubCLIService.swift` | |
| `CLIServices/GitService.swift` | `GitHubService/GitService.swift` | |
| `AWSLocalServices/LocalService.swift` | `LocalDevelopmentService/Protocols/LocalService.swift` | |
| `AWSLocalServices/PostgreSQLLocalService.swift` | `LocalDevelopmentService/Containers/PostgreSQLLocalService.swift` | |
| `AWSLocalServices/MinIOService.swift` | `LocalDevelopmentService/Containers/MinIOService.swift` | |
| `AWSLocalServices/DynamoDBLocalService.swift` | `LocalDevelopmentService/Containers/DynamoDBLocalService.swift` | |
| `LambdaServices/LambdaService.swift` | `LambdaService/Protocols/LambdaService.swift` | |
| `LambdaServices/LambdaBuildService.swift` | `LambdaService/LambdaBuildService.swift` | |
| `Services/CDK/*` | `CDKService/Models/` and `CDKService/Errors/` | Split by type |
| `Services/AWSTestingService.swift` | `AWSService/AWSTestingService.swift` | |
| `Services/GitHubActionsService.swift` | `GitHubService/GitHubActionsService.swift` | |
| `Services/XcodeLocalDevelopmentService.swift` | `LocalDevelopmentService/XcodeLocalDevelopmentService.swift` | |
| `Services/LinuxLocalDevelopmentService.swift` | `LocalDevelopmentService/LinuxLocalDevelopmentService.swift` | |
| `Services/RemoteDeploymentService.swift` | `RemoteDeploymentService/RemoteDeploymentService.swift` | |
| `Services/DependencyCheckerService.swift` | `Core/DependencyCheckerService.swift` | |
| `Services/EnviromentVariables.swift` | `LocalDevelopmentService/EnvironmentVariables.swift` | Fix typo |
| `AWSAuthConfiguration.swift` | `AWSService/AWSAuthConfiguration.swift` | |
| `GitHubConfiguration.swift` | `GitHubService/GitHubConfiguration.swift` | |
| `DeploymentOptions.swift` | `CDKService/Models/DeploymentConfiguration.swift` | Rename for consistency |
| `DeployError.swift` | `Core/Errors/DeployError.swift` | |
| `BuildState.swift` | Split into `LambdaService/Models/` and `LambdaService/Errors/` | Extract BuildError, BuildStatus |

## Naming Conventions

| Type | Suffix | Examples |
|------|--------|----------|
| Input settings | `Configuration` | `AWSAuthConfiguration`, `DeploymentConfiguration` |
| Runtime state | `State` or `Status` | `BuildState`, `CDKInfrastructureStatus` |
| Operation results | `Outputs` or `Result` | `CDKStackOutputs` |
| Error types | `Error` | `BuildError`, `DeployError` |
| Protocols | Service or -able | `LambdaService`, `LocalService` |

## Implementation Notes

1. **Incremental migration**: Move one service at a time to minimize disruption
2. **Fix typos during migration**: `EnviromentVariables` → `EnvironmentVariables`
3. **Split mixed files**: Extract `BuildError` and `BuildStatus` from `BuildState.swift`
4. **Rename for consistency**: `DeploymentOptions` → `DeploymentConfiguration`
