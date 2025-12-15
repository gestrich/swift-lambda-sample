import CLIKit
import Foundation

/// Stateless service for CDK Infrastructure queries and operations
/// Provides methods for querying CloudFormation state and executing CDK commands
public actor CDKInfrastructureQueryService {
    private let cdkService: CDKService
    private let awsService: AWSCLIService

    // MARK: - Initialization

    public init(
        projectRoot: String,
        awsConfig: AWSAuthConfiguration,
        cdkDirectory: String = "cdk",
        cliService: CLIService
    ) {
        self.cdkService = CDKService(
            cdkDirectory: "\(projectRoot)/\(cdkDirectory)",
            awsConfig: awsConfig,
            cliService: cliService
        )
        self.awsService = AWSCLIService(awsConfig: awsConfig, cliService: cliService)
    }

    // MARK: - Query Operations

    /// Get current CloudFormation stack status
    /// - Parameter stackName: Name of the stack
    /// - Returns: Status string (e.g., "CREATE_COMPLETE", "UPDATE_IN_PROGRESS")
    public func getStackStatus(stackName: String) async throws -> String {
        try await awsService.getStackStatus(name: stackName)
    }

    /// Get stack outputs from CloudFormation
    /// - Parameter stackName: Name of the stack
    /// - Returns: Dictionary of output key-value pairs
    public func getStackOutputs(stackName: String) async throws -> [String: String] {
        try await awsService.getStackOutputs(name: stackName)
    }

    /// Query current infrastructure configuration from CloudFormation resources
    /// - Parameter stackName: Name of the stack
    /// - Returns: Configuration indicating what's deployed
    public func queryConfiguration(stackName: String) async throws -> CDKInfrastructureConfiguration {
        let resources = try await awsService.describeStackResources(name: stackName)

        return CDKInfrastructureConfiguration(
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

    /// Get stack events for deployment progress tracking
    /// - Parameters:
    ///   - stackName: Name of the stack
    ///   - limit: Maximum number of events to return
    /// - Returns: Array of stack events
    public func getStackEvents(stackName: String, limit: Int = 50) async throws -> [CloudFormationStackEvent] {
        try await awsService.getStackEvents(name: stackName, limit: limit)
    }

    // MARK: - CDK Operations

    /// Build CDK TypeScript
    /// - Parameter output: Optional stream to receive output
    public func build(output: CLIOutputStream? = nil) async throws {
        try await cdkService.build(output: output)
    }

    /// Deploy CDK stack
    /// - Parameters:
    ///   - withPostgres: Include PostgreSQL database
    ///   - withNATGateway: Include NAT Gateway
    ///   - output: Optional stream to receive output
    public func deploy(
        withPostgres: Bool,
        withNATGateway: Bool,
        output: CLIOutputStream? = nil
    ) async throws {
        let options = CDKService.DeployOptions(
            skipPostgres: !withPostgres,
            skipNATGateway: !withNATGateway,
            requireApproval: false
        )
        try await cdkService.deploy(options: options, output: output)
    }

    /// Destroy CDK stack
    /// - Parameter output: Optional stream to receive output
    public func destroy(output: CLIOutputStream? = nil) async throws {
        try await cdkService.destroy(force: true, output: output)
    }
}

// MARK: - Data Types

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

/// Parsed stack output values
public struct CDKStackOutputs: Equatable, Sendable {
    public let apiGatewayUrl: String?
    public let lambdaFunctionName: String?
    public let bucketName: String?
    public let allOutputs: [String: String]

    public init(
        apiGatewayUrl: String? = nil,
        lambdaFunctionName: String? = nil,
        bucketName: String? = nil,
        allOutputs: [String: String] = [:]
    ) {
        self.apiGatewayUrl = apiGatewayUrl
        self.lambdaFunctionName = lambdaFunctionName
        self.bucketName = bucketName
        self.allOutputs = allOutputs
    }

    public static func from(_ outputs: [String: String]) -> CDKStackOutputs {
        CDKStackOutputs(
            apiGatewayUrl: outputs["ApiGatewayUrl"],
            lambdaFunctionName: outputs["LambdaFunctionName"],
            bucketName: outputs["BucketName"],
            allOutputs: outputs
        )
    }
}

/// CloudFormation stack status values
/// See: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-describing-stacks.html
public enum CloudFormationStackStatusValues {
    // Successful states
    public static let createComplete = "CREATE_COMPLETE"
    public static let updateComplete = "UPDATE_COMPLETE"

    // In-progress states
    public static let createInProgress = "CREATE_IN_PROGRESS"
    public static let updateInProgress = "UPDATE_IN_PROGRESS"
    public static let updateCompleteCleanupInProgress = "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS"
    public static let deleteInProgress = "DELETE_IN_PROGRESS"

    // Failed states
    public static let createFailed = "CREATE_FAILED"
    public static let updateFailed = "UPDATE_FAILED"
    public static let rollbackComplete = "ROLLBACK_COMPLETE"
    public static let rollbackFailed = "ROLLBACK_FAILED"
    public static let deleteFailed = "DELETE_FAILED"

    /// Check if status indicates the stack is successfully deployed
    public static func isDeployed(_ status: String) -> Bool {
        status == createComplete || status == updateComplete
    }

    /// Check if status indicates an in-progress operation
    public static func isInProgress(_ status: String) -> Bool {
        switch status {
        case createInProgress, updateInProgress, updateCompleteCleanupInProgress, deleteInProgress:
            return true
        default:
            return false
        }
    }

    /// Check if status indicates a failed state
    public static func isFailed(_ status: String) -> Bool {
        switch status {
        case createFailed, updateFailed, rollbackComplete, rollbackFailed, deleteFailed:
            return true
        default:
            return false
        }
    }

    /// Check if status indicates a delete operation in progress
    public static func isDeleting(_ status: String) -> Bool {
        status == deleteInProgress
    }
}
