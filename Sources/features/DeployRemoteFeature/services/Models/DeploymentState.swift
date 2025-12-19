import Foundation
import AWSSDK
import GitHubSDK

// MARK: - DeploymentSnapshot (Stable State)

/// Represents stable deployment state when not operating.
/// This is the service-layer state type that use cases yield on completion.
public struct DeploymentSnapshot: Sendable, Equatable {
    public let status: DeploymentStatus
    public let outputs: CDKStackOutputs?
    public let infrastructure: CDKInfrastructureConfiguration?

    public init(
        status: DeploymentStatus,
        outputs: CDKStackOutputs?,
        infrastructure: CDKInfrastructureConfiguration?
    ) {
        self.status = status
        self.outputs = outputs
        self.infrastructure = infrastructure
    }

    public enum DeploymentStatus: Sendable, Equatable {
        case notDeployed
        case deployed(DeployedStack)
        case failed(reason: String)
        case credentialExpired(message: String)
    }

    // MARK: - Convenience Accessors

    public var deployedStack: DeployedStack? {
        if case .deployed(let stack) = status { return stack }
        return nil
    }

    public var apiGatewayUrl: String? { outputs?.apiGatewayUrl }
    public var bucketName: String? { outputs?.bucketName }
    public var lambdaFunctionName: String? { outputs?.lambdaFunctionName }

    public var endpoint: String { apiGatewayUrl ?? "https://<not-configured>" }
    public var isConfigured: Bool { apiGatewayUrl != nil }
    public var isDeployed: Bool { deployedStack != nil }

    public var isCredentialExpired: Bool {
        if case .credentialExpired = status { return true }
        return false
    }

    public var errorMessage: String? {
        switch status {
        case .failed(let reason): return reason
        case .credentialExpired(let message): return message
        default: return nil
        }
    }

    public var canDeploy: Bool {
        switch status {
        case .notDeployed, .deployed, .failed: return true
        case .credentialExpired: return false
        }
    }

    public var canDestroy: Bool {
        if case .deployed = status { return true }
        return false
    }

    // MARK: - Factory Methods

    /// Create from CloudFormation state
    public static func from(_ cfState: CloudFormationState) -> DeploymentSnapshot {
        let stack = cfState.deployedStack
        let status: DeploymentStatus
        switch cfState {
        case .unknown, .loading, .notDeployed:
            status = .notDeployed
        case .deployed(let deployedStack):
            status = .deployed(deployedStack)
        case .deploying, .destroying:
            status = .notDeployed
        case .failed(let reason):
            status = .failed(reason: reason)
        case .credentialExpired(let message):
            status = .credentialExpired(message: message)
        }
        return DeploymentSnapshot(
            status: status,
            outputs: stack.map { CDKStackOutputs.from($0.outputs) },
            infrastructure: stack.map { CDKInfrastructureConfiguration($0.infrastructure) }
        )
    }

    /// Create a not-deployed snapshot
    public static var notDeployed: DeploymentSnapshot {
        DeploymentSnapshot(status: .notDeployed, outputs: nil, infrastructure: nil)
    }

    /// Create a failed snapshot
    public static func failed(reason: String) -> DeploymentSnapshot {
        DeploymentSnapshot(status: .failed(reason: reason), outputs: nil, infrastructure: nil)
    }

    /// Create a failed snapshot preserving prior outputs/infrastructure
    public static func failed(reason: String, preserving prior: DeploymentSnapshot?) -> DeploymentSnapshot {
        DeploymentSnapshot(
            status: .failed(reason: reason),
            outputs: prior?.outputs,
            infrastructure: prior?.infrastructure
        )
    }
}

// MARK: - UseCaseState (What use cases yield)

/// State yielded by a running use case.
/// Use cases capture `startTime` internally; the app layer adds `prior` when constructing ModelState.
public enum UseCaseState: Sendable, Equatable {
    case deploying(DeployProgress)
    case destroying(DestroyProgress)
    case updatingLambda(UpdateLambdaProgress)
    case completed(DeploymentSnapshot)

    // MARK: - Deploy Progress

    /// Progress info for deploy operations
    public struct DeployProgress: Sendable, Equatable {
        public let step: Step
        public let startTime: Date
        public let detail: DeploymentProgress?

        public enum Step: Sendable, Equatable {
            case building
            case deploying
            case monitoring
        }

        public init(step: Step, startTime: Date, detail: DeploymentProgress? = nil) {
            self.step = step
            self.startTime = startTime
            self.detail = detail
        }
    }

    // MARK: - Destroy Progress

    /// Progress info for destroy operations
    public struct DestroyProgress: Sendable, Equatable {
        public let step: Step
        public let startTime: Date
        public let detail: DeploymentProgress?

        public enum Step: Sendable, Equatable {
            case destroying
        }

        public init(step: Step, startTime: Date, detail: DeploymentProgress? = nil) {
            self.step = step
            self.startTime = startTime
            self.detail = detail
        }
    }

    // MARK: - Update Lambda Progress

    /// Progress info for Lambda update operations
    public struct UpdateLambdaProgress: Sendable, Equatable {
        public let step: Step
        public let startTime: Date
        public let runDetail: GitHubRunDetail?

        public enum Step: Sendable, Equatable {
            case checkingGitStatus
            case pushing
            case triggeringWorkflow
            case waitingForWorkflow
            case monitoringWorkflow(runId: String)
        }

        public init(step: Step, startTime: Date, runDetail: GitHubRunDetail? = nil) {
            self.step = step
            self.startTime = startTime
            self.runDetail = runDetail
        }
    }

    // MARK: - Convenience Accessors

    /// Start time extracted from any in-progress state
    public var startTime: Date? {
        switch self {
        case .deploying(let p): return p.startTime
        case .destroying(let p): return p.startTime
        case .updatingLambda(let p): return p.startTime
        case .completed: return nil
        }
    }

    /// Final snapshot if completed
    public var completedSnapshot: DeploymentSnapshot? {
        if case .completed(let snapshot) = self { return snapshot }
        return nil
    }

    /// Whether this is a deploy operation
    public var isDeploying: Bool {
        if case .deploying = self { return true }
        return false
    }

    /// Whether this is a destroy operation
    public var isDestroying: Bool {
        if case .destroying = self { return true }
        return false
    }

    /// Whether this is a Lambda update operation
    public var isUpdatingLambda: Bool {
        if case .updatingLambda = self { return true }
        return false
    }
}
