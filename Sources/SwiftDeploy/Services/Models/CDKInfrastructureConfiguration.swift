import Foundation

/// Detected infrastructure configuration from CloudFormation
public struct CDKInfrastructureConfiguration: Equatable, Sendable {
    public let hasDatabase: Bool
    public let hasNATGateway: Bool
    public let hasVPC: Bool

    public init(hasDatabase: Bool = false, hasNATGateway: Bool = false, hasVPC: Bool = false) {
        self.hasDatabase = hasDatabase
        self.hasNATGateway = hasNATGateway
        self.hasVPC = hasVPC
    }
}
