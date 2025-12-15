import sdk_cli
import sdk_aws
import Foundation

/// App-specific service for detecting Swift Lambda infrastructure configuration.
/// Uses the generic CloudFormationService from sdk-aws for queries, but contains
/// app-specific logic for detecting Database, NAT Gateway, and VPC resources.
public actor SwiftLambdaInfrastructureService {
    private let cloudFormation: CloudFormationService
    private let stackName: String

    public init(
        cloudFormation: CloudFormationService,
        stackName: String = CDKStackConfiguration.defaultStackName
    ) {
        self.cloudFormation = cloudFormation
        self.stackName = stackName
    }

    /// Convenience initializer using AWSAuthConfiguration
    public init(
        awsConfig: AWSAuthConfiguration,
        cliService: CLIClient,
        stackName: String = CDKStackConfiguration.defaultStackName
    ) {
        self.cloudFormation = CloudFormationService(
            credentialProvider: awsConfig.makeCredentialProvider(),
            cliService: cliService
        )
        self.stackName = stackName
    }

    // MARK: - Infrastructure Detection

    /// Detect the current infrastructure configuration from CloudFormation resources
    /// - Returns: The detected infrastructure configuration, or nil if stack doesn't exist
    public func detectConfiguration() async throws -> CDKInfrastructureConfiguration? {
        do {
            let resources = try await cloudFormation.describeStackResources(name: stackName)
            return parseConfiguration(from: resources)
        } catch let error as CloudFormationError {
            if case .commandFailed(_, _, let output) = error,
               output.contains("does not exist") {
                return nil
            }
            throw error
        }
    }

    /// Parse infrastructure configuration from CloudFormation resources
    /// Contains app-specific detection logic for this project's resources
    private func parseConfiguration(from resources: [CloudFormationStackResource]) -> CDKInfrastructureConfiguration {
        CDKInfrastructureConfiguration(
            hasDatabase: resources.contains {
                $0.logicalResourceId.contains("Database") &&
                $0.resourceType.contains("RDS")
            },
            hasNATGateway: resources.contains {
                $0.resourceType == "AWS::EC2::NatGateway"
            },
            hasVPC: resources.contains {
                $0.resourceType == "AWS::EC2::VPC"
            }
        )
    }

    // MARK: - Stack Queries

    /// Get stack outputs parsed as app-specific CDKStackOutputs
    public func getStackOutputs() async throws -> CDKStackOutputs {
        let outputs = try await cloudFormation.getStackOutputs(name: stackName)
        return CDKStackOutputs.from(outputs)
    }

    /// Get raw stack outputs as dictionary
    public func getRawStackOutputs() async throws -> [String: String] {
        try await cloudFormation.getStackOutputs(name: stackName)
    }

    /// Get stack status
    public func getStackStatus() async throws -> String {
        try await cloudFormation.getStackStatus(name: stackName)
    }

    /// Check if the stack exists
    public func stackExists() async throws -> Bool {
        try await cloudFormation.stackExists(name: stackName)
    }

    /// Get stack events for progress tracking
    public func getStackEvents(limit: Int = 50) async throws -> [CloudFormationStackEvent] {
        try await cloudFormation.getStackEvents(name: stackName, limit: limit)
    }

    /// Get stack resources
    public func getStackResources() async throws -> [CloudFormationStackResource] {
        try await cloudFormation.describeStackResources(name: stackName)
    }

    // MARK: - Convenience Accessors

    /// Get the API Gateway URL from stack outputs
    public func getAPIGatewayURL() async throws -> String? {
        let outputs = try await getStackOutputs()
        return outputs.apiGatewayUrl
    }

    /// Get the Lambda function name from stack outputs
    public func getLambdaFunctionName() async throws -> String? {
        let outputs = try await getStackOutputs()
        return outputs.lambdaFunctionName
    }

    /// Get the S3 bucket name from stack outputs
    public func getBucketName() async throws -> String? {
        let outputs = try await getStackOutputs()
        return outputs.bucketName
    }
}
