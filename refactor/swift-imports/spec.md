# Swift Import Alphabetical Sorting

## Overview
Reorder import statements in Swift files to be alphabetically sorted. This improves code consistency and makes it easier to identify duplicate imports.

## Guidelines

1. **Sort all imports alphabetically** - Order import statements from A to Z (case-insensitive)
2. **Preserve grouping comments** - Keep any `// MARK:` or similar comments but sort imports within their groups
3. **One import per line** - Each import should be on its own line
4. **No duplicate imports** - If you find duplicates, remove them
5. **Foundation stays where it is** - If Foundation is imported, keep it in its current position relative to other imports (many Swift files conventionally have Foundation first or second)

## Example

**Before:**
```swift
import Foundation
import ArgumentParser
import DeployLocalService
import DeployCoreService
import DeployLinuxFeature
import LocalServicesFeature
```

**After:**
```swift
import ArgumentParser
import DeployCoreService
import DeployLinuxFeature
import DeployLocalService
import Foundation
import LocalServicesFeature
```

## Checklist

- [ ] Sort imports in all files starting with A-C (APIClient.swift, APIGatewayHandler.swift, APIGatewayRequestWrapper.swift, APIGatewayResponseWrapper.swift, AppModel.swift, AWSAuthConfiguration.swift, AWSAuthConfiguration+ArgumentParser.swift, AWSAuthConfiguration+Persistence.swift, AWSCLIClient.swift, AWSCommand.swift, AWSCredentialErrorBanner.swift, AWSCredentialErrorView.swift, AWSCredentialProvider.swift, AWSVaultClient.swift, Brew.swift, BrewClient.swift, BrewError.swift, BuildError.swift, BuildScript.swift, BuildState.swift, BuildStatus.swift, CDKClient.swift, CDKCommand.swift, CDKInfrastructureConfiguration.swift, CDKInfrastructureSectionView.swift, CDKOutputParser.swift, CDKProgress.swift, CDKStackConfiguration.swift, CDKStackOutputs.swift, CLIApp/main.swift, CLIArgument.swift, CLIAWSEnvironment.swift, CLIClient.swift, CLIClientError.swift, CLICommand.swift, CLICommandMacro.swift, CLIOutputStream.swift, CLIOutputParser.swift, CLIProgramMacro.swift, CLIProgram.swift, CLITool.swift, CLIToolStatus.swift, ClientService.swift, ClientView.swift, CloudFormationClient.swift, CloudFormationState.swift, CloudWatchHandler.swift, CloudWatchLogsClient.swift, CloudWatchLogsModel.swift, CloudWatchLogsSectionView.swift, CloudWatchLogsUseCase.swift, CollapsibleOutputPanel.swift, CommandInputView.swift, Configuration.swift, ConfigurationService.swift, ContentView.swift, CopyableEndpointView.swift, CreateReminderRequest.swift, CreateUser.swift, CreateUserHandler.swift, CreateUserRequest.swift, Curl.swift)
- [ ] Sort imports in all files starting with D-F (DependencyInstallUseCase.swift, DependencySnapshot.swift, DependencyStatusModel.swift, DependencyStatusUseCase.swift, DeployCommand.swift, DeployError.swift, DeployInitCommand.swift, DeployInitUseCase.swift, DeployLinuxCommand.swift, DeployLinuxModel.swift, DeployLinuxProgressPrinters.swift, DeploymentConfiguration.swift, DeploymentProgress.swift, DeploymentState.swift, DeployRemoteCommand.swift, DeployRemoteModel.swift, DeployStatusUseCase.swift, DeployUseCase.swift, DeployXcodeCommand.swift, DeployXcodeModel.swift, DeployXcodeProgressPrinters.swift, DestroyUseCase.swift, DirectInvocationEvent.swift, Docker.swift, DockerClient.swift, DockerError.swift, DockerServicesView.swift, DynamicLambaHandler.swift, DynamoDBClient.swift, DynamoDBConfiguration.swift, DynamoDBDataStoreAWS.swift, DynamoDBDataStoreInterface.swift, DynamoDBDataStoreProduction.swift, EnvironmentVariables.swift, ExecutionResult.swift, FileDownloadResponse.swift, FileModels.swift, FileUploadRequest.swift)
- [ ] Sort imports in all files starting with G-M (Gh.swift, Git.swift, GitClient.swift, GitHubCIModel.swift, GitHubCISectionView.swift, GitHubCITypes.swift, GitHubCLIClient.swift, GitHubClientError.swift, GitHubConfiguration.swift, GitHubMonitorRunUseCase.swift, GitHubPushAndDeployUseCase.swift, GitHubStatusQuery.swift, GitHubTypes.swift, Homebrew.swift, Id.swift, InfrastructureShape.swift, Kill.swift, LambdaBuildService.swift, LambdaClient.swift, LambdaEvent.swift, LambdaHandler.swift, LambdaPaths.swift, LambdaResponse.swift, LambdaService.swift, LambdaState.swift, LambdaStatus.swift, LambdaUpdateView.swift, LambdaUploadSectionView.swift, LinuxBuildUseCase.swift, LinuxContainerConfig.swift, LinuxCopyConfigUseCase.swift, LinuxDeploymentState.swift, LinuxRunInteractiveUseCase.swift, LinuxSetupNetworkUseCase.swift, LinuxStartAllUseCase.swift, LinuxStartLambdaUseCase.swift, LinuxStatusUseCase.swift, LinuxStopAllUseCase.swift, LinuxStopLambdaUseCase.swift, LinuxTestUseCase.swift, LocalService.swift, LocalServiceType.swift, LocalServicesConfiguration.swift, LocalServicesModel.swift, LocalServicesSnapshot.swift, LocalServicesUseCaseState.swift, LocalServiceView.swift, LocalStorageService.swift, Ls.swift, Lsof.swift, MacApp/main.swift, Macros.swift, MinIOClient.swift)
- [ ] Sort imports in all files starting with N-S (Node.swift, NodeClient.swift, NodeError.swift, Npm.swift, NpmClient.swift, Open.swift, OperationOutputSection.swift, Plugin.swift, PostgresConfiguration.swift, PostgresModelStore.swift, PostgresModelStoreInterface.swift, PostgresModelStoreProduction.swift, PostgreSQLClient.swift, PostgresView.swift, PrincipleDetailView.swift, ProjectPathResolver.swift, PropertyMacros.swift, RefreshUseCase.swift, Reminder.swift, RemindersView.swift, RemoteServiceView.swift, ResumeMonitoringUseCase.swift, Rm.swift, S3Client.swift, S3Configuration.swift, S3DataStoreInterface.swift, S3DataStoreProduction.swift, S3DataStoreS3.swift, S3View.swift, SecretsManagerClient.swift, SecretsServiceAWS.swift, SecretsServiceInterface.swift, SecretsServiceProduction.swift, ServiceComposer.swift, ServicesStatusUseCase.swift, SettingsView.swift, SetupViews.swift, Sh.swift, StartServicesUseCase.swift, StatusCommand.swift, StatusPrinter.swift, StopServicesUseCase.swift, StorageKeys.swift, StreamingTextView.swift, StreamingUseCase.swift, StringUtils.swift, StyleModifiers.swift, SwiftCLI.swift, SwiftServerApp.swift)
- [ ] Sort imports in all files starting with T-Z (TearDownCommand.swift, Which.swift, UpdateLambdaCommand.swift, UpdateLambdaUseCase.swift, UpdateReminderRequest.swift, UpdateUser.swift, UpdateUserRequest.swift, UploadLambdaCommand.swift, UseCase.swift, UseCaseError.swift, User.swift, UserFormView.swift, XcodeBuildUseCase.swift, XcodeCopyConfigUseCase.swift, XcodeDeploymentState.swift, XcodeStartAllUseCase.swift, XcodeStartLambdaUseCase.swift, XcodeStatusUseCase.swift, XcodeStopAllUseCase.swift, XcodeStopLambdaUseCase.swift, XcodeTestUseCase.swift)
