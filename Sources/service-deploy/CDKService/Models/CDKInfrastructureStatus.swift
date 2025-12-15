import Foundation

/// Mutable state container for CDK Infrastructure tracking
/// Used by models to hold observable UI state
public struct CDKInfrastructureStatus: Equatable, Sendable {
    /// Current stack status
    public enum StackStatus: Equatable, Sendable {
        case unknown
        case loading
        case notDeployed
        case deployed
        case deploying(operation: String)
        case destroying
        case failed(reason: String)

        public var isDeploying: Bool {
            if case .deploying = self { return true }
            return false
        }

        public var isDestroying: Bool {
            if case .destroying = self { return true }
            return false
        }

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
    }

    public var status: StackStatus = .unknown
    public var configuration: CDKInfrastructureConfiguration = CDKInfrastructureConfiguration()
    public var outputs: CDKStackOutputs = CDKStackOutputs()
    public var stackName: String
    public var deployStartTime: Date?
    public var deploymentProgress: CDKDeploymentProgress = CDKDeploymentProgress()

    public init(stackName: String = CDKStackConfiguration.defaultStackName) {
        self.stackName = stackName
    }

    /// Convenience computed properties for UI
    public var hasPolled: Bool { deploymentProgress.pollCount > 0 }
    public var hasPolledEnough: Bool { deploymentProgress.pollCount >= 5 }
}
