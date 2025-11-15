import Foundation

/// Deployment configuration options
public struct DeploymentOptions: Sendable {
    /// Whether to skip PostgreSQL database deployment
    public let skipPostgres: Bool

    /// Whether to skip NAT Gateway deployment (saves cost but limits Lambda internet access)
    public let skipNATGateway: Bool

    /// AWS profile to use for deployment
    public let awsProfile: String

    /// Working directory for CDK operations
    public let cdkDirectory: String

    public init(
        skipPostgres: Bool = false,
        skipNATGateway: Bool = false,
        awsProfile: String = "production",
        cdkDirectory: String = "cdk"
    ) {
        self.skipPostgres = skipPostgres
        self.skipNATGateway = skipNATGateway
        self.awsProfile = awsProfile
        self.cdkDirectory = cdkDirectory
    }
}
