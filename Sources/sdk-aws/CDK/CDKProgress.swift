import Foundation

/// Progress updates from CDK operations.
/// Used by stateless stream-returning methods.
public enum CDKProgress: Sendable {
    /// Installing npm dependencies
    case installing

    /// Building TypeScript CDK code
    case building

    /// Deploying CDK stack with progress updates
    case deploying(DeploymentProgress)

    /// Successfully deployed with stack outputs
    case deployed(outputs: [String: String])

    /// Destroying CDK stack with progress updates
    case destroying(DeploymentProgress)

    /// Successfully destroyed
    case destroyed
}
