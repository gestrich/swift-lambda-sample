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

        public var isDeploying: Bool {
            if case .deploy = self { return true }
            return false
        }

        public var isDestroying: Bool {
            if case .destroy = self { return true }
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
    public convenience init(
        projectRoot: String,
        cliClient: CLIClient? = nil
    ) {
        let awsConfig = AWSAuthConfiguration.loadConfig() ?? AWSAuthConfiguration(profileName: "default", useAWSVault: false)
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

    /// App-specific deployment options (mirrors service-deploy for compatibility)
    public struct DeployOptions: Sendable {
        public let withPostgres: Bool
        public let withNATGateway: Bool
        public let requireApproval: Bool

        public init(
            withPostgres: Bool = false,
            withNATGateway: Bool = false,
            requireApproval: Bool = false
        ) {
            self.withPostgres = withPostgres
            self.withNATGateway = withNATGateway
            self.requireApproval = requireApproval
        }

        public static var minimal: DeployOptions {
            DeployOptions(withPostgres: false, withNATGateway: false)
        }

        public static var full: DeployOptions {
            DeployOptions(withPostgres: true, withNATGateway: true)
        }

        func toWorkflowOptions() -> DeployWorkflow.Options {
            DeployWorkflow.Options(
                withPostgres: withPostgres,
                withNATGateway: withNATGateway,
                requireApproval: requireApproval
            )
        }
    }

    /// Deploy infrastructure with specified configuration
    public func deploy(options: DeployOptions, output: CLIOutputStream? = nil) async {
        guard canDeploy else { return }

        lastError = nil
        operationStartTime = Date()

        let workflow = DeployWorkflow(
            cdkClient: cdkClient,
            cfClient: cfClient,
            stackName: stackName
        )

        do {
            for try await progress in workflow.run(options: options.toWorkflowOptions(), output: output) {
                activeWorkflow = .deploy(progress)

                // Update state based on workflow progress
                switch progress.step {
                case .building:
                    deploymentState = .deploying(operation: .building, progress: DeploymentProgress(), startTime: operationStartTime ?? Date())

                case .deploying:
                    if case .cdk(let deployProgress) = progress.detail {
                        deploymentState = .deploying(operation: .deploying, progress: deployProgress, startTime: operationStartTime ?? Date())
                    }

                case .monitoring:
                    if case .cdk(let deployProgress) = progress.detail {
                        deploymentState = .deploying(operation: .monitoring, progress: deployProgress, startTime: operationStartTime ?? Date())
                    }

                case .complete:
                    if case .outputs(let outputs, let config) = progress.detail {
                        stackOutputs = outputs
                        infrastructureConfiguration = config
                        if let outputs = outputs {
                            deploymentState = .deployed(outputs: outputs.allOutputs)
                        }
                    }
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
        let hasDatabase = infrastructureConfiguration?.hasDatabase ?? false
        let hasNATGateway = infrastructureConfiguration?.hasNATGateway ?? false

        let options = DeployOptions(withPostgres: hasDatabase, withNATGateway: hasNATGateway)
        await deploy(options: options, output: output)
    }

    // MARK: - Destroy Operations

    /// Destroy infrastructure
    public func destroy(output: CLIOutputStream? = nil) async {
        guard canDestroy else { return }

        lastError = nil
        operationStartTime = Date()

        let workflow = DestroyWorkflow(
            cdkClient: cdkClient,
            cfClient: cfClient,
            stackName: stackName
        )

        do {
            for try await progress in workflow.run(output: output) {
                activeWorkflow = .destroy(progress)

                // Update state based on workflow progress
                switch progress.step {
                case .destroying:
                    if let deployProgress = progress.detail {
                        deploymentState = .destroying(progress: deployProgress, startTime: operationStartTime ?? Date())
                    } else {
                        deploymentState = .destroying(progress: DeploymentProgress(), startTime: operationStartTime ?? Date())
                    }

                case .complete:
                    deploymentState = .notDeployed
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
        guard let githubClient = githubClient else {
            throw DeployError.configurationMissing(
                file: "~/.swiftSampleDemo/github-config.json",
                hint: "Create with: {\"repository\": \"owner/repo\", \"branch\": \"dev\"}"
            )
        }

        if !skipPush {
            let hasCommitsToPush = try await gitClient.hasCommitsToPush()

            if hasCommitsToPush {
                let beforeRunId = try await githubClient.getLatestRunId()
                try await gitClient.push()

                try await githubClient.waitForNewWorkflowCompletion(
                    afterRunId: beforeRunId,
                    timeoutMinutes: 10
                )
            } else {
                print("\n✅ No commits to push")
                print("🔄 Triggering workflow to redeploy current code...\n")
                try await githubClient.triggerWorkflowAndWait(
                    workflowName: "Dev Deploy",
                    timeoutMinutes: 10
                )
            }
        } else {
            print("\n⏭️  Skipping git push (--skip-push enabled)")
            print("🔄 Triggering workflow...\n")
            try await githubClient.triggerWorkflowAndWait(
                workflowName: "Dev Deploy",
                timeoutMinutes: 10
            )
        }
    }

    // MARK: - Private: App-Specific State

    /// Update app-specific state (infrastructureConfiguration, stackOutputs) based on deployment state.
    private func updateAppSpecificState() async throws {
        switch deploymentState {
        case .deployed(let outputs):
            infrastructureConfiguration = try await detectConfiguration()
            stackOutputs = CDKStackOutputs.from(outputs)

        case .notDeployed:
            infrastructureConfiguration = nil
            stackOutputs = nil

        default:
            break
        }
    }

    /// Detect the current infrastructure configuration from CloudFormation resources
    private func detectConfiguration() async throws -> CDKInfrastructureConfiguration? {
        do {
            let resources = try await cfClient.describeStackResources(name: stackName)
            return parseConfiguration(from: resources)
        } catch let error as CloudFormationError {
            if case .commandFailed(_, _, let output) = error,
               output.contains("does not exist") {
                return nil
            }
            throw error
        }
    }

    /// Parse infrastructure configuration from CloudFormation resources
    private func parseConfiguration(from resources: [CloudFormationStackResource]) -> CDKInfrastructureConfiguration {
        CDKInfrastructureConfiguration(
            hasDatabase: resources.contains {
                $0.logicalResourceId.contains("Database") &&
                $0.resourceType.contains("RDS")
            },
            hasNATGateway: resources.contains {
                $0.resourceType == "AWS::EC2::NatGateway"
            },
            hasVPC: resources.contains {
                $0.resourceType == "AWS::EC2::VPC"
            }
        )
    }
}
