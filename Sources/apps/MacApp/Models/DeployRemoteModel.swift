import Foundation
import AWSSDK
import CLISDK
import ClientService
import GitHubSDK
import DeployRemoteFeature
import DeployCoreService

/// Observable model for remote AWS deployments in the app layer.
/// This is a thin model that uses workflows from service-deploy-remote and maintains observable state.
///
/// Per the layered architecture:
/// - App layer (this model): @Observable state + UI coordination
/// - Service layer (workflows): Multi-step orchestration, returns AsyncThrowingStream
/// - SDK layer (clients): Stateless execute/query operations
@MainActor @Observable
public class DeployRemoteModel {
    // MARK: - Persistence Key

    public static let persistenceKey = "remote"

    // MARK: - Unified State Machine

    /// Single source of truth for all model state
    public private(set) var state: ModelState = .uninitialized

    /// Last error from a workflow (kept separate for error display after operation completes)
    public private(set) var lastOperationError: Error?

    // MARK: - Configuration

    /// Stack name being managed
    public let stackName: String

    /// Project root directory
    public let projectRoot: String

    /// AWS configuration (exposed for auxiliary services)
    public let awsConfig: AWSAuthConfiguration

    /// GitHub configuration (exposed for auxiliary services)
    public let githubConfig: GitHubActionsConfiguration?
    
    // MARK: - SDK Clients

    private let cdkClient: CDKClient
    private let cfClient: CloudFormationClient
    public let cliClient: CLIClient

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
    
    // MARK: - Derived State (Convenience Accessors)

    /// Whether any workflow is currently active
    public var isIdle: Bool {
        state.isIdle
    }

    /// Whether a deploy operation can be started
    public var canDeploy: Bool {
        state.canDeploy
    }

    /// Whether a destroy operation can be started
    public var canDestroy: Bool {
        state.canDestroy
    }

    /// Whether Lambda code can be updated (via GitHub Actions)
    public var canUpdateLambda: Bool {
        state.isIdle && (githubConfig != nil)
    }

    /// API client for making requests to this service
    public var apiClient: APIClient {
        APIClient(baseURL: state.endpoint, mode: .remote, serviceName: "Remote")
    }

    /// Operation start time (for elapsed time display) - derived from state
    public var operationStartTime: Date? {
        state.operationStartTime
    }

    // MARK: - Refresh Operations

    /// Refresh deployment state from AWS
    /// If an operation is in progress, automatically starts monitoring it via RefreshWorkflow.
    public func refresh() async {
        guard state.isIdle else { return }

        lastOperationError = nil
        let prior = state.snapshot
        state = .loading(prior: prior)

        let workflow = RefreshWorkflow(cfClient: cfClient, stackName: stackName)

        do {
            for try await workflowState in workflow.stream(options: ()) {
                state = ModelState(from: workflowState, prior: prior)
            }
        } catch {
            lastOperationError = error
            state = .ready(.failed(reason: error.localizedDescription, preserving: prior))
        }
    }

    // MARK: - Deploy Operations

    /// Deploy infrastructure with specified configuration
    public func deploy(options: DeployWorkflow.Options) async {
        guard state.canDeploy else { return }

        lastOperationError = nil
        let prior = state.snapshot

        let workflow = DeployWorkflow(
            cdkClient: cdkClient,
            cfClient: cfClient,
            stackName: stackName
        )

        do {
            for try await workflowState in workflow.stream(options: options) {
                state = ModelState(from: workflowState, prior: prior)
            }
        } catch {
            lastOperationError = error
            state = .ready(.failed(reason: error.localizedDescription, preserving: prior))
        }
    }

    /// Update infrastructure maintaining current configuration
    public func updateInfrastructure(output: CLIOutputStream? = nil) async {
        let shape = state.snapshot?.infrastructure?.shape ?? .minimal
        let options = DeployWorkflow.Options(infrastructure: shape, output: output)
        await deploy(options: options)
    }

    // MARK: - Destroy Operations

    /// Destroy infrastructure
    public func destroy(output: CLIOutputStream? = nil) async {
        guard state.canDestroy else { return }

        lastOperationError = nil
        let prior = state.snapshot

        let workflow = DestroyWorkflow(
            cdkClient: cdkClient,
            cfClient: cfClient,
            stackName: stackName
        )

        let options = DestroyWorkflow.Options(output: output)
        do {
            for try await workflowState in workflow.stream(options: options) {
                state = ModelState(from: workflowState, prior: prior)
            }
        } catch {
            lastOperationError = error
            state = .ready(.failed(reason: error.localizedDescription, preserving: prior))
        }
    }

    // MARK: - Lambda Code Updates

    /// Update Lambda code via GitHub Actions
    public func updateLambdaCode(skipPush: Bool = false) async throws {
        guard state.isIdle else { return }

        lastOperationError = nil
        let prior = state.snapshot

        let workflow = try UpdateLambdaWorkflow.create(
            projectRoot: projectRoot,
            cliClient: cliClient
        )

        let options = UpdateLambdaWorkflow.Options(skipPush: skipPush)

        do {
            for try await workflowState in workflow.stream(options: options) {
                state = ModelState(from: workflowState, prior: prior)
            }
            // Stream finished without .completed - restore prior state
            if let snapshot = prior {
                state = .ready(snapshot)
            } else {
                state = .ready(.notDeployed)
            }
        } catch {
            lastOperationError = error
            if let snapshot = prior {
                state = .ready(snapshot)
            } else {
                state = .ready(.failed(reason: error.localizedDescription))
            }
            throw error
        }
    }

    // MARK: - Nested Types

    /// Unified state machine for the deployment model.
    /// Makes invalid states unrepresentable by encoding all state combinations in the type system.
    ///
    /// Uses service-layer types (`WorkflowState`, `DeploymentSnapshot`) for actual state,
    /// while `ModelState` handles the app-layer concerns (loading, prior preservation).
    public enum ModelState {
        /// Initial state before any operation
        case uninitialized

        /// Loading/refreshing state from AWS (preserves prior state if available)
        case loading(prior: DeploymentSnapshot?)

        /// Ready state with current deployment info
        case ready(DeploymentSnapshot)

        /// Active workflow in progress (uses WorkflowState from service layer)
        case operating(WorkflowState, prior: DeploymentSnapshot?)

        // MARK: - Convenience Initializer

        /// Construct ModelState from a workflow state plus app-layer prior.
        /// This is the key integration point between workflows and the model.
        public init(from workflowState: WorkflowState, prior: DeploymentSnapshot?) {
            if let snapshot = workflowState.completedSnapshot {
                self = .ready(snapshot)
            } else {
                self = .operating(workflowState, prior: prior)
            }
        }

        // MARK: - Convenience Accessors

        /// Current deployment info (from ready state or prior state during loading/operation)
        public var snapshot: DeploymentSnapshot? {
            switch self {
            case .uninitialized:
                return nil
            case .loading(let prior):
                return prior
            case .ready(let snapshot):
                return snapshot
            case .operating(_, let prior):
                return prior
            }
        }

        /// The active workflow state, if operating
        public var workflowState: WorkflowState? {
            guard case .operating(let state, _) = self else { return nil }
            return state
        }

        /// Whether the model is idle (not loading or operating)
        public var isIdle: Bool {
            switch self {
            case .uninitialized, .ready:
                return true
            case .loading, .operating:
                return false
            }
        }

        /// Whether a deploy operation can be started
        public var canDeploy: Bool {
            switch self {
            case .ready(let snapshot):
                return snapshot.canDeploy
            case .uninitialized:
                return true
            case .loading, .operating:
                return false
            }
        }

        /// Whether a destroy operation can be started
        public var canDestroy: Bool {
            switch self {
            case .ready(let snapshot):
                return snapshot.canDestroy
            case .uninitialized, .loading, .operating:
                return false
            }
        }

        /// Endpoint URL with fallback
        public var endpoint: String {
            snapshot?.endpoint ?? "https://<not-configured>"
        }

        /// Whether configured (has valid endpoint)
        public var isConfigured: Bool {
            snapshot?.isConfigured ?? false
        }

        /// Whether deployed
        public var isDeployed: Bool {
            snapshot?.isDeployed ?? false
        }

        /// Error message if in error state
        public var errorMessage: String? {
            snapshot?.errorMessage
        }

        /// Outputs from current snapshot
        public var outputs: CDKStackOutputs? {
            snapshot?.outputs
        }

        /// Infrastructure from current snapshot
        public var infrastructure: CDKInfrastructureConfiguration? {
            snapshot?.infrastructure
        }

        /// Operation start time (for elapsed time display) - from workflow state
        public var operationStartTime: Date? {
            workflowState?.startTime
        }
    }
}
