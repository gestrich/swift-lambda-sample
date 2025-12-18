import Foundation

/// Infrastructure components detected from CloudFormation stack resources.
/// This is an SDK-level type representing what was actually deployed.
public struct DetectedInfrastructure: Sendable, Equatable {
    public let hasDatabase: Bool
    public let hasNATGateway: Bool
    public let hasVPC: Bool

    public init(hasDatabase: Bool = false, hasNATGateway: Bool = false, hasVPC: Bool = false) {
        self.hasDatabase = hasDatabase
        self.hasNATGateway = hasNATGateway
        self.hasVPC = hasVPC
    }

    public init(resources: [CloudFormationStackResource]) {
        self.hasDatabase = resources.hasDatabase
        self.hasNATGateway = resources.hasNATGateway
        self.hasVPC = resources.hasVPC
    }
}

/// Represents a successfully deployed CloudFormation stack.
/// Bundles outputs and infrastructure detection since they're fetched together.
public struct DeployedStack: Sendable, Equatable {
    public let outputs: [String: String]
    public let infrastructure: DetectedInfrastructure

    public init(outputs: [String: String] = [:], infrastructure: DetectedInfrastructure = DetectedInfrastructure()) {
        self.outputs = outputs
        self.infrastructure = infrastructure
    }
}

/// High-level state machine for CloudFormation stack lifecycle.
///
/// This is the SDK-layer state type representing the overall stack status.
/// It embeds `DeploymentProgress` for resource-level details during operations.
///
/// ## Usage
///
/// - `CloudFormationClient.queryState()` return type
/// - `CloudFormationClient.monitorStream()` yields
/// - `DeployRemoteModel.deploymentState` for stable state display
///
/// ## Progress Type Hierarchy
///
/// This type sits between resource-level tracking and workflow-level tracking:
///
/// ```
/// DeploymentProgress (sdk-aws) - individual resources
///     └── embedded in CloudFormationState (sdk-aws) ← YOU ARE HERE
///         └── consumed by DeployWorkflow.Progress (service-deploy-remote)
///             └── consumed by ActiveWorkflow (feature-mac)
/// ```
public enum CloudFormationState: Sendable, Equatable {
    /// Operations that can occur during deployment
    public enum DeployOperation: String, Sendable, Equatable {
        case building = "Building"
        case deploying = "Deploying"
        case monitoring = "Monitoring"
        case updating = "Updating"  // Generic in-progress state from CloudFormation queries
    }

    case unknown
    case loading
    case notDeployed
    case deployed(DeployedStack)
    case deploying(operation: DeployOperation, progress: DeploymentProgress, startTime: Date)
    case destroying(progress: DeploymentProgress, startTime: Date)
    case failed(reason: String)
    case credentialExpired(message: String)

    public var isBusy: Bool {
        switch self {
        case .loading, .deploying, .destroying:
            return true
        default:
            return false
        }
    }

    public var canDeploy: Bool {
        switch self {
        case .loading, .deploying, .destroying:
            return false
        default:
            return true
        }
    }

    public var canDestroy: Bool {
        switch self {
        case .deployed:
            return true
        default:
            return false
        }
    }

    public var deployedStack: DeployedStack? {
        if case .deployed(let stack) = self {
            return stack
        }
        return nil
    }

    public var outputs: [String: String] {
        deployedStack?.outputs ?? [:]
    }

    public var infrastructure: DetectedInfrastructure? {
        deployedStack?.infrastructure
    }

    public var progress: DeploymentProgress {
        switch self {
        case .deploying(_, let progress, _), .destroying(let progress, _):
            return progress
        default:
            return DeploymentProgress()
        }
    }

    public var operationStartTime: Date? {
        switch self {
        case .deploying(_, _, let startTime), .destroying(_, let startTime):
            return startTime
        default:
            return nil
        }
    }

    public var operationName: String? {
        if case .deploying(let operation, _, _) = self {
            return operation.rawValue
        }
        return nil
    }

    public var operation: DeployOperation? {
        if case .deploying(let operation, _, _) = self {
            return operation
        }
        return nil
    }
}

/// CloudFormation stack status values.
/// See: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-describing-stacks.html
public enum StackStatus {
    public static let createComplete = "CREATE_COMPLETE"
    public static let updateComplete = "UPDATE_COMPLETE"

    public static let createInProgress = "CREATE_IN_PROGRESS"
    public static let updateInProgress = "UPDATE_IN_PROGRESS"
    public static let updateCompleteCleanupInProgress = "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS"
    public static let deleteInProgress = "DELETE_IN_PROGRESS"

    public static let createFailed = "CREATE_FAILED"
    public static let updateFailed = "UPDATE_FAILED"
    public static let rollbackComplete = "ROLLBACK_COMPLETE"
    public static let rollbackFailed = "ROLLBACK_FAILED"
    public static let deleteFailed = "DELETE_FAILED"

    public static func isDeployed(_ status: String) -> Bool {
        status == createComplete || status == updateComplete
    }

    public static func isInProgress(_ status: String) -> Bool {
        switch status {
        case createInProgress, updateInProgress, updateCompleteCleanupInProgress, deleteInProgress:
            return true
        default:
            return false
        }
    }

    public static func isFailed(_ status: String) -> Bool {
        switch status {
        case createFailed, updateFailed, rollbackComplete, rollbackFailed, deleteFailed:
            return true
        default:
            return false
        }
    }

    public static func isDeleting(_ status: String) -> Bool {
        status == deleteInProgress
    }
}

/// Typed errors for CloudFormation deployment operations.
public enum DeploymentError: Error, Equatable, Sendable {
    case credentialExpired(message: String)
    case stackNotFound(stackName: String)
    case deploymentFailed(reason: String)
    case buildFailed(reason: String)
    case operationInProgress(operation: String)
    case unknown(message: String)

    public var localizedDescription: String {
        switch self {
        case .credentialExpired(let message):
            return "AWS credentials expired: \(message)"
        case .stackNotFound(let stackName):
            return "Stack not found: \(stackName)"
        case .deploymentFailed(let reason):
            return "Deployment failed: \(reason)"
        case .buildFailed(let reason):
            return "Build failed: \(reason)"
        case .operationInProgress(let operation):
            return "Operation in progress: \(operation)"
        case .unknown(let message):
            return message
        }
    }

    /// Check if an error message indicates AWS credential issues
    public static func isCredentialError(_ error: String) -> Bool {
        let credentialPatterns = [
            "credentials missing",
            "credential_process",
            "Error getting temporary credentials",
            "ExpiredToken",
            "InvalidClientTokenId",
            "AccessDenied",
            "AuthFailure",
            "security token included in the request is invalid",
            "could not be found"
        ]
        return credentialPatterns.contains { error.localizedCaseInsensitiveContains($0) }
    }

    /// Check if an error message indicates the stack doesn't exist
    public static func isStackNotFoundError(_ error: String) -> Bool {
        let notFoundPatterns = [
            "does not exist",
            "Stack with id",
            "ValidationError"
        ]
        return notFoundPatterns.contains { error.localizedCaseInsensitiveContains($0) }
    }
}
