import Foundation

/// Represents infrastructure configuration shape.
/// Used for both desired state (what to deploy) and detected state (what's deployed).
///
/// This is the unified type that bridges:
/// - `DeployWorkflow.Options` (desired state for deployment)
/// - `CDKInfrastructureConfiguration` (detected state from CloudFormation)
///
/// By using the same shape type, conversions between desired and detected state
/// become straightforward and the field names are consistent.
public struct InfrastructureShape: Sendable, Equatable {
    public let hasDatabase: Bool
    public let hasNATGateway: Bool

    public init(hasDatabase: Bool = false, hasNATGateway: Bool = false) {
        self.hasDatabase = hasDatabase
        self.hasNATGateway = hasNATGateway
    }

    /// Minimal infrastructure: no database, no NAT Gateway
    public static var minimal: InfrastructureShape {
        InfrastructureShape(hasDatabase: false, hasNATGateway: false)
    }

    /// Full infrastructure: database and NAT Gateway included
    public static var full: InfrastructureShape {
        InfrastructureShape(hasDatabase: true, hasNATGateway: true)
    }
}
