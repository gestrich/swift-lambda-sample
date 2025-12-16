import Foundation
import sdk_aws

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
}

extension CloudFormationClient {
    /// Detect infrastructure configuration from CloudFormation resources.
    /// Returns nil if the stack does not exist.
    public func detectConfiguration(stackName: String) async throws -> CDKInfrastructureConfiguration? {
        do {
            let resources = try await describeStackResources(name: stackName)
            return CDKInfrastructureConfiguration(resources: resources)
        } catch let error as CloudFormationError {
            if case .commandFailed(_, _, let output) = error,
               output.contains("does not exist") {
                return nil
            }
            throw error
        }
    }
}
