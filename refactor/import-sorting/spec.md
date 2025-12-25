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

### Files A-B
- [ ] Sort imports in APIClient.swift
- [ ] Sort imports in APIGatewayHandler.swift
- [ ] Sort imports in APIGatewayRequestWrapper.swift
- [ ] Sort imports in APIGatewayResponseWrapper.swift
- [ ] Sort imports in AppModel.swift
- [ ] Sort imports in AWSAuthConfiguration.swift
- [ ] Sort imports in AWSAuthConfiguration+ArgumentParser.swift
- [ ] Sort imports in AWSAuthConfiguration+Persistence.swift
- [ ] Sort imports in AWSCLIClient.swift
- [ ] Sort imports in AWSCommand.swift
- [ ] Sort imports in AWSCredentialErrorBanner.swift
- [ ] Sort imports in AWSCredentialErrorView.swift
- [ ] Sort imports in AWSCredentialProvider.swift
- [ ] Sort imports in AWSVaultClient.swift
- [ ] Sort imports in Brew.swift
- [ ] Sort imports in BrewClient.swift
- [ ] Sort imports in BrewError.swift
- [ ] Sort imports in BuildError.swift
- [ ] Sort imports in BuildScript.swift
- [ ] Sort imports in BuildState.swift
- [ ] Sort imports in BuildStatus.swift

### Files C
- [ ] Sort imports in CDKClient.swift
- [ ] Sort imports in CDKCommand.swift
- [ ] Sort imports in CDKInfrastructureConfiguration.swift
- [ ] Sort imports in CDKInfrastructureSectionView.swift
- [ ] Sort imports in CDKOutputParser.swift
- [ ] Sort imports in CDKProgress.swift
- [ ] Sort imports in CDKStackConfiguration.swift
- [ ] Sort imports in CDKStackOutputs.swift
- [ ] Sort imports in CLIApp/main.swift
- [ ] Sort imports in CLIArgument.swift
- [ ] Sort imports in CLIAWSEnvironment.swift
- [ ] Sort imports in CLIClient.swift
- [ ] Sort imports in CLIClientError.swift
- [ ] Sort imports in CLICommand.swift
- [ ] Sort imports in CLICommandMacro.swift
- [ ] Sort imports in CLIOutputStream.swift
- [ ] Sort imports in CLIOutputParser.swift
- [ ] Sort imports in CLIProgramMacro.swift
- [ ] Sort imports in CLIProgram.swift
- [ ] Sort imports in CLITool.swift
- [ ] Sort imports in CLIToolStatus.swift
- [ ] Sort imports in ClientService.swift (if it exists)
- [ ] Sort imports in ClientView.swift
- [ ] Sort imports in CloudFormationClient.swift
- [ ] Sort imports in CloudFormationState.swift
- [ ] Sort imports in CloudWatchHandler.swift
- [ ] Sort imports in CloudWatchLogsClient.swift
- [ ] Sort imports in CloudWatchLogsModel.swift
- [ ] Sort imports in CloudWatchLogsSectionView.swift
- [ ] Sort imports in CloudWatchLogsUseCase.swift
- [ ] Sort imports in CollapsibleOutputPanel.swift
- [ ] Sort imports in CommandInputView.swift
- [ ] Sort imports in Configuration.swift
- [ ] Sort imports in ConfigurationService.swift
- [ ] Sort imports in ContentView.swift
- [ ] Sort imports in CopyableEndpointView.swift
- [ ] Sort imports in CreateReminderRequest.swift
- [ ] Sort imports in CreateUser.swift
- [ ] Sort imports in CreateUserHandler.swift
- [ ] Sort imports in CreateUserRequest.swift
- [ ] Sort imports in Curl.swift

### Files D-E
- [ ] Sort imports in DependencyInstallUseCase.swift
- [ ] Sort imports in DependencySnapshot.swift
- [ ] Sort imports in DependencyStatusModel.swift
- [ ] Sort imports in DependencyStatusUseCase.swift
- [ ] Sort imports in DeployCommand.swift
- [ ] Sort imports in DeployError.swift
- [ ] Sort imports in DeployInitCommand.swift
- [ ] Sort imports in DeployInitUseCase.swift
- [ ] Sort imports in DeployLinuxCommand.swift
- [ ] Sort imports in DeployLinuxModel.swift
- [ ] Sort imports in DeployLinuxProgressPrinters.swift
- [ ] Sort imports in DeploymentConfiguration.swift
- [ ] Sort imports in DeploymentProgress.swift
- [ ] Sort imports in DeploymentState.swift
- [ ] Sort imports in DeployRemoteCommand.swift
- [ ] Sort imports in DeployRemoteModel.swift
- [ ] Sort imports in DeployStatusUseCase.swift
- [ ] Sort imports in DeployUseCase.swift
- [ ] Sort imports in DeployXcodeCommand.swift
- [ ] Sort imports in DeployXcodeModel.swift
- [ ] Sort imports in DeployXcodeProgressPrinters.swift
- [ ] Sort imports in DestroyUseCase.swift
- [ ] Sort imports in DirectInvocationEvent.swift
- [ ] Sort imports in Docker.swift
- [ ] Sort imports in DockerClient.swift
- [ ] Sort imports in DockerError.swift
- [ ] Sort imports in DockerServicesView.swift
- [ ] Sort imports in DynamicLambaHandler.swift
- [ ] Sort imports in DynamoDBClient.swift
- [ ] Sort imports in DynamoDBConfiguration.swift
- [ ] Sort imports in DynamoDBDataStoreAWS.swift
- [ ] Sort imports in DynamoDBDataStoreInterface.swift
- [ ] Sort imports in DynamoDBDataStoreProduction.swift
- [ ] Sort imports in EnvironmentVariables.swift
- [ ] Sort imports in ExecutionResult.swift

### Files F-I
- [ ] Sort imports in FileDownloadResponse.swift
- [ ] Sort imports in FileModels.swift
- [ ] Sort imports in FileUploadRequest.swift
- [ ] Sort imports in Gh.swift
- [ ] Sort imports in Git.swift
- [ ] Sort imports in GitClient.swift
- [ ] Sort imports in GitHubCIModel.swift
- [ ] Sort imports in GitHubCISectionView.swift
- [ ] Sort imports in GitHubCITypes.swift
- [ ] Sort imports in GitHubCLIClient.swift
- [ ] Sort imports in GitHubClientError.swift
- [ ] Sort imports in GitHubConfiguration.swift
- [ ] Sort imports in GitHubMonitorRunUseCase.swift
- [ ] Sort imports in GitHubPushAndDeployUseCase.swift
- [ ] Sort imports in GitHubStatusQuery.swift
- [ ] Sort imports in GitHubTypes.swift
- [ ] Sort imports in Homebrew.swift
- [ ] Sort imports in Id.swift
- [ ] Sort imports in InfrastructureShape.swift

### Files K-M
- [ ] Sort imports in Kill.swift
- [ ] Sort imports in LambdaBuildService.swift
- [ ] Sort imports in LambdaClient.swift
- [ ] Sort imports in LambdaEvent.swift
- [ ] Sort imports in LambdaHandler.swift
- [ ] Sort imports in LambdaPaths.swift
- [ ] Sort imports in LambdaResponse.swift
- [ ] Sort imports in LambdaService.swift
- [ ] Sort imports in LambdaState.swift
- [ ] Sort imports in LambdaStatus.swift
- [ ] Sort imports in LambdaUpdateView.swift
- [ ] Sort imports in LambdaUploadSectionView.swift
- [ ] Sort imports in LinuxBuildUseCase.swift
- [ ] Sort imports in LinuxContainerConfig.swift
- [ ] Sort imports in LinuxCopyConfigUseCase.swift
- [ ] Sort imports in LinuxDeploymentState.swift
- [ ] Sort imports in LinuxRunInteractiveUseCase.swift
- [ ] Sort imports in LinuxSetupNetworkUseCase.swift
- [ ] Sort imports in LinuxStartAllUseCase.swift
- [ ] Sort imports in LinuxStartLambdaUseCase.swift
- [ ] Sort imports in LinuxStatusUseCase.swift
- [ ] Sort imports in LinuxStopAllUseCase.swift
- [ ] Sort imports in LinuxStopLambdaUseCase.swift
- [ ] Sort imports in LinuxTestUseCase.swift
- [ ] Sort imports in LocalService.swift
- [ ] Sort imports in LocalServiceType.swift
- [ ] Sort imports in LocalServicesConfiguration.swift
- [ ] Sort imports in LocalServicesModel.swift
- [ ] Sort imports in LocalServicesSnapshot.swift
- [ ] Sort imports in LocalServicesUseCaseState.swift
- [ ] Sort imports in LocalServiceView.swift
- [ ] Sort imports in LocalStorageService.swift
- [ ] Sort imports in Ls.swift
- [ ] Sort imports in Lsof.swift
- [ ] Sort imports in MacApp/main.swift
- [ ] Sort imports in Macros.swift
- [ ] Sort imports in MinIOClient.swift

### Files N-P
- [ ] Sort imports in Node.swift
- [ ] Sort imports in NodeClient.swift
- [ ] Sort imports in NodeError.swift
- [ ] Sort imports in Npm.swift
- [ ] Sort imports in NpmClient.swift
- [ ] Sort imports in Open.swift
- [ ] Sort imports in OperationOutputSection.swift
- [ ] Sort imports in Plugin.swift
- [ ] Sort imports in PostgresConfiguration.swift
- [ ] Sort imports in PostgresModelStore.swift
- [ ] Sort imports in PostgresModelStoreInterface.swift
- [ ] Sort imports in PostgresModelStoreProduction.swift
- [ ] Sort imports in PostgreSQLClient.swift
- [ ] Sort imports in PostgresView.swift
- [ ] Sort imports in PrincipleDetailView.swift
- [ ] Sort imports in ProjectPathResolver.swift
- [ ] Sort imports in PropertyMacros.swift

### Files R-S
- [ ] Sort imports in RefreshUseCase.swift
- [ ] Sort imports in Reminder.swift
- [ ] Sort imports in RemindersView.swift
- [ ] Sort imports in RemoteServiceView.swift
- [ ] Sort imports in ResumeMonitoringUseCase.swift
- [ ] Sort imports in Rm.swift
- [ ] Sort imports in S3Client.swift
- [ ] Sort imports in S3Configuration.swift
- [ ] Sort imports in S3DataStoreInterface.swift
- [ ] Sort imports in S3DataStoreProduction.swift
- [ ] Sort imports in S3DataStoreS3.swift
- [ ] Sort imports in S3View.swift
- [ ] Sort imports in SecretsManagerClient.swift
- [ ] Sort imports in SecretsServiceAWS.swift
- [ ] Sort imports in SecretsServiceInterface.swift
- [ ] Sort imports in SecretsServiceProduction.swift
- [ ] Sort imports in ServiceComposer.swift
- [ ] Sort imports in ServicesStatusUseCase.swift
- [ ] Sort imports in SettingsView.swift
- [ ] Sort imports in SetupViews.swift
- [ ] Sort imports in Sh.swift
- [ ] Sort imports in StartServicesUseCase.swift
- [ ] Sort imports in StatusCommand.swift
- [ ] Sort imports in StatusPrinter.swift
- [ ] Sort imports in StopServicesUseCase.swift
- [ ] Sort imports in StorageKeys.swift
- [ ] Sort imports in StreamingTextView.swift
- [ ] Sort imports in StreamingUseCase.swift
- [ ] Sort imports in StringUtils.swift
- [ ] Sort imports in StyleModifiers.swift
- [ ] Sort imports in SwiftCLI.swift
- [ ] Sort imports in SwiftServerApp.swift

### Files T-W
- [ ] Sort imports in TearDownCommand.swift
- [ ] Sort imports in Which.swift

### Files X-Z and U
- [ ] Sort imports in UpdateLambdaCommand.swift
- [ ] Sort imports in UpdateLambdaUseCase.swift
- [ ] Sort imports in UpdateReminderRequest.swift
- [ ] Sort imports in UpdateUser.swift
- [ ] Sort imports in UpdateUserRequest.swift
- [ ] Sort imports in UploadLambdaCommand.swift
- [ ] Sort imports in UseCase.swift
- [ ] Sort imports in UseCaseError.swift
- [ ] Sort imports in User.swift
- [ ] Sort imports in UserFormView.swift
- [ ] Sort imports in XcodeBuildUseCase.swift
- [ ] Sort imports in XcodeCopyConfigUseCase.swift
- [ ] Sort imports in XcodeDeploymentState.swift
- [ ] Sort imports in XcodeStartAllUseCase.swift
- [ ] Sort imports in XcodeStartLambdaUseCase.swift
- [ ] Sort imports in XcodeStatusUseCase.swift
- [ ] Sort imports in XcodeStopAllUseCase.swift
- [ ] Sort imports in XcodeStopLambdaUseCase.swift
- [ ] Sort imports in XcodeTestUseCase.swift
