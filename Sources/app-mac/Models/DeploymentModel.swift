import Foundation
import sdk_aws
import sdk_cli
import sdk_client
import sdk_github
import service_deploy

/// Observable model for remote AWS deployments in the app layer.
/// This is a thin model that uses workflows from service-deploy and maintains observable state.
///
/// Per the layered architecture:
/// - App layer (this model): @Observable state + UI coordination
/// - Service layer (workflows): Multi-step orchestration, returns AsyncThrowingStream
/// - SDK layer (clients): Stateless execute/query operations
@MainActor @Observable
public class DeploymentModel {
    // MARK: - Stable State

    /// High-level deployment state (derived from SDK states + CloudFormation queries)
    public private(set) var deploymentState: CloudFormationState = .unknown

    /// Parsed stack outputs
    public private(set) var stackOutputs: CDKStackOutputs?

    /// Detected infrastructure configuration from CloudFormation
    public private(set) var infrastructureConfiguration: CDKInfrastructureConfiguration?

    // MARK: - Transient Workflow State

    /// Currently active workflow (if any)
    public private(set) var activeWorkflow: ActiveWorkflow?

    /// Represents an active workflow with its progress
    public enum ActiveWorkflow {
        case deploy(DeployWorkflow.Progress)
        case destroy(DestroyWorkflow.Progress)
        case updateLambda(UpdateLambdaWorkflow.Progress)

        public var isDeploying: Bool {
            if case .deploy = self { return true }
            return false
        }

        public var isDestroying: Bool {
            if case .destroy = self { return true }
            return false
        }

        public var isUpdatingLambda: Bool {
            if case .updateLambda = self { return true }
            return false
        }
    }

    // MARK: - Error State

    /// Last error from a workflow (cleared when new workflow starts)
    public private(set) var lastError: Error?

    // MARK: - Operation Timing

    /// Operation start time (for elapsed time display)
    public private(set) var operationStartTime: Date?

    // MARK: - SDK Clients

    private let cdkClient: CDKClient
    private let cfClient: CloudFormationClient
    private let githubClient: GitHubActionsClient?
    private let gitClient: GitClient

    /// CLI client for executing commands (exposed for auxiliary services)
    public let cliClient: CLIClient

    // MARK: - Configuration

    /// Stack name being managed
    public let stackName: String

    /// Project root directory
    public let projectRoot: String

    /// AWS configuration (exposed for auxiliary services)
    public let awsConfig: AWSAuthConfiguration

    /// GitHub configuration (exposed for auxiliary services)
    public let githubConfig: GitHubActionsConfiguration?

    // MARK: - Derived State

    /// Whether any workflow is currently active
    public var isIdle: Bool {
        activeWorkflow == nil
    }

    /// Whether a deploy operation can be started
    public var canDeploy: Bool {
        isIdle && deploymentState.canDeploy
    }

    /// Whether a destroy operation can be started
    public var canDestroy: Bool {
        isIdle && deploymentState.canDestroy
    }

    /// Whether Lambda code can be updated (via GitHub Actions)
    public var canUpdateLambda: Bool {
        isIdle && (githubClient != nil)
    }

    /// API Gateway URL from stack outputs
    public var apiGatewayUrl: String? {
        stackOutputs?.apiGatewayUrl
    }

    /// Endpoint URL (alias for apiGatewayUrl for compatibility)
    public var endpoint: String {
        apiGatewayUrl ?? "https://<not-configured>"
    }

    /// Whether the service is configured (has a valid endpoint)
    public var isConfigured: Bool {
        apiGatewayUrl != nil
    }

    /// API client for making requests to this service
    public var apiClient: APIClient {
        APIClient(baseURL: endpoint, mode: .remote, serviceName: "Remote")
    }

    /// Lambda function name from stack outputs
    public var lambdaFunctionName: String? {
        stackOutputs?.lambdaFunctionName
    }

    /// S3 bucket name from stack outputs
    public var bucketName: String? {
        stackOutputs?.bucketName
    }

    /// Whether infrastructure is deployed
    public var isDeployed: Bool {
        if case .deployed = deploymentState { return true }
        return false
    }

    /// Whether credentials have expired
    public var isCredentialExpired: Bool {
        if case .credentialExpired = deploymentState { return true }
        return false
    }

    /// Error message if in failed state
    public var errorMessage: String? {
        if case .failed(let reason) = deploymentState { return reason }
        if case .credentialExpired(let message) = deploymentState { return message }
        return nil
    }

    // MARK: - Initialization

    public init(
        projectRoot: String,
        awsConfig: AWSAuthConfiguration,
        githubConfig: GitHubActionsConfiguration? = nil,
        cdkDirectory: String = CDKStackConfiguration.defaultCDKDirectory,
        stackName: String = CDKStackConfiguration.defaultStackName,
        cliClient: CLIClient? = nil
    ) {
        self.projectRoot = projectRoot
        self.stackName = stackName
        self.awsConfig = awsConfig
        self.githubConfig = githubConfig

        let cli = cliClient ?? CLIClient(defaultWorkingDirectory: projectRoot)
        self.cliClient = cli

        let credentialProvider = awsConfig.makeCredentialProvider()
        let fullCdkPath = "\(projectRoot)/\(cdkDirectory)"

        self.cdkClient = CDKClient(
            cdkDirectory: fullCdkPath,
            credentialProvider: credentialProvider,
            cliClient: cli
        )

        self.cfClient = CloudFormationClient(
            credentialProvider: credentialProvider,
            cliClient: cli
        )

        self.gitClient = GitClient(repoPath: projectRoot, cliClient: cli)

        if let githubConfig = githubConfig {
            self.githubClient = GitHubActionsClient(
                repoPath: projectRoot,
                config: githubConfig,
                cliClient: cli
            )
        } else {
            self.githubClient = nil
        }
    }

    /// Convenience initializer that loads configs from disk
    /// - Throws: `DeployError.configurationMissing` if AWS config file is not found
    public convenience init(
        projectRoot: String,
        cliClient: CLIClient? = nil
    ) throws {
        guard let awsConfig = AWSAuthConfiguration.loadConfig() else {
            throw DeployError.configurationMissing(
                file: AWSAuthConfiguration.configPath,
                hint: "Run 'swift run SwiftDeploy local copy-config' to create"
            )
        }
        let githubConfig = GitHubConfiguration.loadConfig()?.toSDKConfiguration()

        self.init(
            projectRoot: projectRoot,
            awsConfig: awsConfig,
            githubConfig: githubConfig,
            cliClient: cliClient
        )
    }

    // MARK: - Refresh Operations

    /// Refresh deployment state from AWS
    public func refresh() async {
        guard isIdle else { return }

        deploymentState = .loading

        do {
            let queriedState = try await cfClient.queryState(stackName: stackName)
            deploymentState = queriedState

            // Update app-specific state based on deployment state
            try await updateAppSpecificState()
        } catch let error as DeploymentError {
            if case .credentialExpired(let message) = error {
                deploymentState = .credentialExpired(message: message)
            } else {
                deploymentState = .failed(reason: error.localizedDescription)
            }
        } catch {
            deploymentState = .failed(reason: error.localizedDescription)
        }
    }

    // MARK: - Deploy Operations

    /// Deploy infrastructure with specified configuration
    public func deploy(options: DeployWorkflow.Options, output: CLIOutputStream? = nil) async {
        guard canDeploy else { return }

        lastError = nil
        let startTime = Date()
        operationStartTime = startTime

        let workflow = DeployWorkflow(
            cdkClient: cdkClient,
            cfClient: cfClient,
            stackName: stackName
        )

        do {
            for try await progress in workflow.run(options: options, output: output) {
                activeWorkflow = .deploy(progress)
                deploymentState = progress.toDeploymentState(startTime: startTime)

                // Extract app-specific state on completion
                if progress.step == .complete {
                    stackOutputs = progress.stackOutputs
                    infrastructureConfiguration = progress.infrastructureConfiguration
                }
            }
        } catch {
            lastError = error
            deploymentState = .failed(reason: error.localizedDescription)
        }

        activeWorkflow = nil
        operationStartTime = nil
    }

    /// Update infrastructure maintaining current configuration
    public func updateInfrastructure(output: CLIOutputStream? = nil) async {
        let shape = infrastructureConfiguration?.shape ?? .minimal
        let options = DeployWorkflow.Options(infrastructure: shape)
        await deploy(options: options, output: output)
    }

    // MARK: - Destroy Operations

    /// Destroy infrastructure
    public func destroy(output: CLIOutputStream? = nil) async {
        guard canDestroy else { return }

        lastError = nil
        let startTime = Date()
        operationStartTime = startTime

        let workflow = DestroyWorkflow(
            cdkClient: cdkClient,
            cfClient: cfClient,
            stackName: stackName
        )

        do {
            for try await progress in workflow.run(output: output) {
                activeWorkflow = .destroy(progress)
                deploymentState = progress.toDeploymentState(startTime: startTime)

                // Clear app-specific state on completion
                if progress.step == .complete {
                    stackOutputs = nil
                    infrastructureConfiguration = nil
                }
            }
        } catch {
            lastError = error
            deploymentState = .failed(reason: error.localizedDescription)
        }

        activeWorkflow = nil
        operationStartTime = nil
    }

    // MARK: - Lambda Code Updates

    /// Update Lambda code via GitHub Actions
    public func updateLambdaCode(skipPush: Bool = false) async throws {
        let workflow = try UpdateLambdaWorkflow.create(
            projectRoot: projectRoot,
            cliClient: cliClient
        )

        let options = UpdateLambdaWorkflow.Options(skipPush: skipPush)

        for try await progress in workflow.run(options: options) {
            activeWorkflow = .updateLambda(progress)
        }

        activeWorkflow = nil
    }

    // MARK: - Private: App-Specific State

    /// Update app-specific state (infrastructureConfiguration, stackOutputs) based on deployment state.
    private func updateAppSpecificState() async throws {
        switch deploymentState {
        case .deployed(let outputs):
            infrastructureConfiguration = try await cfClient.detectConfiguration(stackName: stackName)
            stackOutputs = CDKStackOutputs.from(outputs)

        case .notDeployed:
            infrastructureConfiguration = nil
            stackOutputs = nil

        default:
            break
        }
    }
}
