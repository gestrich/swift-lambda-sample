import AWSSDK
import ClientService
import CLISDK
import DeployCoreService
import DeployRemoteFeature
import Foundation
import GitHubSDK
import LambdaBuildService

/// Observable model for remote AWS deployments in the app layer.
/// This is a thin model that uses use cases from service-deploy-remote and maintains observable state.
///
/// Per the layered architecture:
/// - App layer (this model): @Observable state + UI coordination
/// - Service layer (use cases): Multi-step orchestration, returns AsyncThrowingStream
/// - SDK layer (clients): Stateless execute/query operations
@MainActor @Observable
public class DeployRemoteModel {
    // MARK: - Persistence Key

    public static let persistenceKey = "remote"

    // MARK: - Unified State Machine

    /// Single source of truth for all model state
    public private(set) var state: ModelState = .uninitialized

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

    // MARK: - Child Models (always available when parent exists)

    /// CloudWatch logs model - available because parent requires AWS config
    public let cloudWatchLogsModel: CloudWatchLogsModel

    /// Lambda build service - available because parent requires AWS config
    public let lambdaBuildService: LambdaBuildService

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

        // Create child models (always available since parent requires AWS config)
        let logsUseCase = CloudWatchLogsUseCase.create(
            cliClient: cli,
            lambdaFunctionName: "swift-lambda-sample",
            credentialProvider: credentialProvider
        )
        self.cloudWatchLogsModel = CloudWatchLogsModel(useCase: logsUseCase)

        self.lambdaBuildService = LambdaBuildService(
            workingDirectory: projectRoot,
            cliClient: cli,
            awsConfig: awsConfig
        )
        Task { await refresh() }
    }

    /// Convenience initializer that loads configs from disk
    /// - Throws: `DeployError.configurationMissing` if AWS config file is not found
    public convenience init(projectRoot: String) throws {
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
            githubConfig: githubConfig
        )
    }

    // MARK: - Derived State (Convenience Accessors)

    /// Whether any use case is currently active
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
    /// If an operation is in progress, automatically starts monitoring it.
    ///
    /// Uses model composition: queries CloudFormation state directly, then
    /// delegates to `ResumeMonitoringUseCase` if an operation is in progress.
    /// This replaces the previous approach where `RefreshUseCase` called
    /// `ResumeMonitoringUseCase` (use case composition).
    public func refresh() async {
        guard state.isIdle else { return }

        let prior = state.snapshot
        state = .loading(prior: prior)

        do {
            let cfState = try await cfClient.queryState(stackName: stackName)

            switch cfState {
            case .deploying, .destroying:
                // Model composition: delegate to monitoring use case
                let monitorUseCase = ResumeMonitoringUseCase(
                    cfClient: cfClient,
                    stackName: stackName
                )
                for try await useCaseState in monitorUseCase.run(initialState: cfState) {
                    state = ModelState(from: useCaseState, prior: prior)
                }

            default:
                // Stable state - yield completed immediately
                let snapshot = DeploymentSnapshot.from(cfState)
                state = .ready(snapshot)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
        }
    }

    // MARK: - Deploy Operations

    /// Deploy infrastructure with specified configuration
    public func deploy(options: DeployUseCase.Options) async {
        guard state.canDeploy else { return }

        let prior = state.snapshot

        let useCase = DeployUseCase(
            cdkClient: cdkClient,
            cfClient: cfClient,
            stackName: stackName
        )

        do {
            for try await useCaseState in useCase.stream(options: options) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
        }
    }

    /// Update infrastructure maintaining current configuration
    public func updateInfrastructure(output: CLIOutputStream? = nil) async {
        let shape = state.snapshot?.infrastructure?.shape ?? .minimal
        let options = DeployUseCase.Options(infrastructure: shape, output: output)
        await deploy(options: options)
    }

    // MARK: - Destroy Operations

    /// Destroy infrastructure
    public func destroy(output: CLIOutputStream? = nil) async {
        guard state.canDestroy else { return }

        let prior = state.snapshot

        let useCase = DestroyUseCase(
            cdkClient: cdkClient,
            cfClient: cfClient,
            stackName: stackName
        )

        let options = DestroyUseCase.Options(output: output)
        do {
            for try await useCaseState in useCase.stream(options: options) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
        }
    }

    // MARK: - Lambda Code Updates

    /// Update Lambda code via GitHub Actions
    public func updateLambdaCode(skipPush: Bool = false) async throws {
        guard state.isIdle else { return }

        let prior = state.snapshot

        let useCase = try UpdateLambdaUseCase.create(
            projectRoot: projectRoot,
            cliClient: cliClient
        )

        let options = UpdateLambdaUseCase.Options(skipPush: skipPush, prior: prior)

        do {
            for try await useCaseState in useCase.stream(options: options) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    // MARK: - Deploy Init (Model Composition)

    /// Options for the deploy-init operation
    public struct DeployInitOptions {
        public let withPostgres: Bool
        public let withNATGateway: Bool
        public let skipPush: Bool

        public init(
            withPostgres: Bool = false,
            withNATGateway: Bool = false,
            skipPush: Bool = false
        ) {
            self.withPostgres = withPostgres
            self.withNATGateway = withNATGateway
            self.skipPush = skipPush
        }
    }

    /// Initial deployment with model composition.
    /// Orchestrates safety checks, infrastructure deployment, Lambda update, database init, and verification.
    /// Uses model composition: calls own `deploy()` and `updateLambdaCode()` methods.
    public func deployInit(options: DeployInitOptions) async throws {
        guard state.canDeploy else { return }

        let prior = state.snapshot
        let startTime = Date()

        do {
            // Phase 1: Safety check - prevent accidental database deletion
            try await checkDatabaseSafety(withPostgres: options.withPostgres)

            // Phase 2: Deploy infrastructure (model composition - calls own deploy method)
            let deployOptions = DeployUseCase.Options(
                withPostgres: options.withPostgres,
                withNATGateway: options.withNATGateway
            )
            await deploy(options: deployOptions)

            // Check if deploy succeeded
            guard let snapshot = state.snapshot, snapshot.isDeployed else {
                throw DeployError.deploymentFailed(reason: "Infrastructure deployment did not complete successfully")
            }

            // Phase 3: Update Lambda code (model composition - calls own updateLambdaCode method)
            try await updateLambdaCode(skipPush: options.skipPush)

            // Phase 4: Initialize database if Postgres is included
            if options.withPostgres, let apiUrl = state.snapshot?.apiGatewayUrl {
                state = .operating(.initializingDatabase(UseCaseState.InitDatabaseProgress(
                    step: .initializing,
                    startTime: startTime
                )), prior: prior)

                let response = try await initializeDatabase(apiUrl: apiUrl)
                state = .operating(.initializingDatabase(UseCaseState.InitDatabaseProgress(
                    step: .completed,
                    startTime: startTime,
                    response: response
                )), prior: prior)
            }

            // Phase 5: Verify deployment
            if let apiUrl = state.snapshot?.apiGatewayUrl {
                state = .operating(.verifyingDeployment(UseCaseState.VerifyProgress(
                    step: .verifying,
                    startTime: startTime
                )), prior: prior)

                let response = try await verifyDeployment(apiUrl: apiUrl)
                state = .operating(.verifyingDeployment(UseCaseState.VerifyProgress(
                    step: .completed,
                    startTime: startTime,
                    response: response
                )), prior: prior)
            }

            // Complete - restore ready state with final snapshot
            if let finalSnapshot = state.snapshot {
                state = .ready(finalSnapshot)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    // MARK: - Deploy Init Private Helpers

    private func checkDatabaseSafety(withPostgres: Bool) async throws {
        do {
            let cfState = try await cfClient.queryState(stackName: stackName)

            if case .deployed = cfState {
                let resources = try await cfClient.describeStackResources(name: stackName)
                let hasExistingDatabase = resources.contains {
                    $0.logicalResourceId.contains("Database") && $0.resourceType.contains("RDS")
                }

                if hasExistingDatabase && !withPostgres {
                    throw DeployError.invalidConfiguration(
                        "Cannot remove database with deploy-init. Use 'tear-down' first if you want to remove the database."
                    )
                }
            }
        } catch let error as DeployError {
            throw error
        } catch {
            // Stack doesn't exist or other error - safe to proceed
        }
    }

    private func initializeDatabase(apiUrl: String) async throws -> String {
        let curlCommand = Curl.Request.post(url: "\(apiUrl)api/database", silent: true)
        let result = try await cliClient.executeForResult(curlCommand, printCommand: false)

        if !result.isSuccess {
            let errorOutput = result.stderr.isEmpty ? result.stdout : result.stderr
            throw DeployError.commandFailed(
                command: "curl POST /api/database",
                exitCode: result.exitCode,
                output: errorOutput
            )
        }

        let response = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if !response.contains("Database Initialized") {
            throw DeployError.deploymentFailed(reason: "Unexpected database init response: \(response)")
        }

        return response
    }

    private func verifyDeployment(apiUrl: String) async throws -> String {
        let healthCommand = Curl.Request.get(url: "\(apiUrl)api/health", silent: true)
        let result = try await cliClient.executeForResult(healthCommand, printCommand: false)

        if !result.isSuccess {
            let errorOutput = result.stderr.isEmpty ? result.stdout : result.stderr
            throw DeployError.testFailed(message: "Health check failed: \(errorOutput)")
        }

        let response = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if response.contains("error") || response.contains("Error") {
            throw DeployError.testFailed(message: "Health check returned error: \(response)")
        }

        return response
    }

    // MARK: - Nested Types

    /// Unified state machine for the deployment model.
    /// Makes invalid states unrepresentable by encoding all state combinations in the type system.
    ///
    /// Uses service-layer types (`UseCaseState`, `DeploymentSnapshot`) for actual state,
    /// while `ModelState` handles the app-layer concerns (loading, prior preservation).
    public enum ModelState {
        /// Initial state before any operation
        case uninitialized

        /// Loading/refreshing state from AWS (preserves prior state if available)
        case loading(prior: DeploymentSnapshot?)

        /// Ready state with current deployment info
        case ready(DeploymentSnapshot)

        /// Active use case in progress (uses UseCaseState from service layer)
        case operating(UseCaseState, prior: DeploymentSnapshot?)

        // MARK: - Convenience Initializers

        /// Construct ModelState from a use case state plus app-layer prior.
        /// This is the key integration point between use cases and the model.
        public init(from useCaseState: UseCaseState, prior: DeploymentSnapshot?) {
            if let snapshot = useCaseState.completedSnapshot {
                self = .ready(snapshot)
            } else {
                self = .operating(useCaseState, prior: prior)
            }
        }

        /// Construct a failed ModelState from a caught error.
        public init(error: Error, preserving prior: DeploymentSnapshot?) {
            self = .ready(.failed(reason: error.localizedDescription, preserving: prior))
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

        /// The active use case state, if operating
        public var useCaseState: UseCaseState? {
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

        /// Operation start time (for elapsed time display) - from use case state
        public var operationStartTime: Date? {
            useCaseState?.startTime
        }
    }
}
