import Foundation
import d_sdk_aws

/// Detected infrastructure configuration from CloudFormation.
/// Extends InfrastructureShape with additional detected properties.
public struct CDKInfrastructureConfiguration: Equatable, Sendable {
    /// Core infrastructure shape (matches desired state type)
    public let shape: InfrastructureShape

    /// Whether VPC was detected (detection-only, not a deployment option)
    public let hasVPC: Bool

    /// Convenience accessor for database status
    public var hasDatabase: Bool { shape.hasDatabase }

    /// Convenience accessor for NAT Gateway status
    public var hasNATGateway: Bool { shape.hasNATGateway }

    public init(hasDatabase: Bool = false, hasNATGateway: Bool = false, hasVPC: Bool = false) {
        self.shape = InfrastructureShape(hasDatabase: hasDatabase, hasNATGateway: hasNATGateway)
        self.hasVPC = hasVPC
    }

    /// Initialize from CloudFormation stack resources
    public init(resources: [CloudFormationStackResource]) {
        self.init(
            hasDatabase: resources.hasDatabase,
            hasNATGateway: resources.hasNATGateway,
            hasVPC: resources.hasVPC
        )
    }

    /// Initialize from SDK-layer detected infrastructure
    public init(_ detected: DetectedInfrastructure) {
        self.init(
            hasDatabase: detected.hasDatabase,
            hasNATGateway: detected.hasNATGateway,
            hasVPC: detected.hasVPC
        )
    }

    /// Convert to SDK-layer detected infrastructure
    public var detectedInfrastructure: DetectedInfrastructure {
        DetectedInfrastructure(
            hasDatabase: hasDatabase,
            hasNATGateway: hasNATGateway,
            hasVPC: hasVPC
        )
    }
}
