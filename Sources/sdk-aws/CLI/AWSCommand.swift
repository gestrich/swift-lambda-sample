import sdk_cli
import Foundation

/// AWS CLI program definition using macro-based API
@CLIProgram
public struct Aws {

    // MARK: - Version

    /// AWS CLI version command
    /// Example: aws --version
    @CLICommand("--version")
    public struct Version {
        public init() {}
    }

    // MARK: - CloudFormation

    /// AWS CloudFormation namespace
    @CLICommand("cloudformation")
    public struct CloudFormation {
        /// AWS CloudFormation describe-stacks command
        /// Example: aws cloudformation describe-stacks --stack-name MyStack --profile prod --output json
        @CLICommand("describe-stacks")
        public struct DescribeStacks {
            /// Stack name to describe
            @Option public var stackName: String

            /// AWS profile to use
            @Option public var profile: String

            /// Output format
            @Option public var output: String?

            /// JMESPath query for filtering output
            @Option public var query: String?
        }

        /// AWS CloudFormation describe-stack-resources command
        /// Example: aws cloudformation describe-stack-resources --stack-name MyStack --profile prod --output json
        @CLICommand("describe-stack-resources")
        public struct DescribeStackResources {
            /// Stack name to describe
            @Option public var stackName: String

            /// AWS profile to use
            @Option public var profile: String

            /// Output format
            @Option public var output: String?
        }

        /// AWS CloudFormation describe-stack-events command
        /// Example: aws cloudformation describe-stack-events --stack-name MyStack --profile prod --output json
        @CLICommand("describe-stack-events")
        public struct DescribeStackEvents {
            /// Stack name to describe
            @Option public var stackName: String

            /// AWS profile to use
            @Option public var profile: String

            /// Output format
            @Option public var output: String?
        }
    }

    // MARK: - Lambda

    /// AWS Lambda namespace
    @CLICommand
    public struct Lambda {
        /// AWS Lambda update-function-code command
        /// Example: aws lambda update-function-code --function-name my-function --zip-file fileb://lambda.zip --profile prod
        @CLICommand("update-function-code")
        public struct UpdateFunctionCode {
            /// Lambda function name
            @Option public var functionName: String

            /// Path to the zip file (should include fileb:// prefix)
            @Option public var zipFile: String

            /// AWS profile to use
            @Option public var profile: String
        }

        /// AWS Lambda get-function command
        /// Example: aws lambda get-function --function-name my-function --profile prod --output json
        @CLICommand("get-function")
        public struct GetFunction {
            /// Lambda function name
            @Option public var functionName: String

            /// AWS profile to use
            @Option public var profile: String

            /// Output format
            @Option public var output: String?
        }
    }

    // MARK: - CloudWatch Logs

    /// AWS Logs namespace
    @CLICommand
    public struct Logs {
        /// AWS Logs tail command
        /// Example: aws logs tail /aws/lambda/my-function --since 5m --format short --follow --profile prod
        @CLICommand
        public struct Tail {
            /// Log group name
            @Positional public var logGroup: String

            /// Show logs from this time (e.g., "5m", "1h")
            @Option public var since: String?

            /// Output format (short, detailed, etc.)
            @Option public var format: String?

            /// Continuously poll for new logs
            @Flag public var follow: Bool = false

            /// AWS profile to use
            @Option public var profile: String
        }
    }

    // MARK: - S3

    /// AWS S3 namespace
    @CLICommand
    public struct S3 {
        /// AWS S3 ls command
        /// Example: aws s3 ls s3://bucket-name/prefix --profile prod
        @CLICommand
        public struct Ls {
            /// S3 path (e.g., s3://bucket-name/ or s3://bucket-name/prefix)
            @Positional public var path: String

            /// AWS profile to use
            @Option public var profile: String
        }

        /// AWS S3 cp command
        /// Example: aws s3 cp s3://bucket/file.txt ./file.txt --profile prod
        @CLICommand
        public struct Cp {
            /// Source path (local or S3)
            @Positional public var source: String

            /// Destination path (local or S3)
            @Positional public var destination: String

            /// AWS profile to use
            @Option public var profile: String
        }
    }

    // MARK: - Secrets Manager

    /// AWS Secrets Manager namespace
    @CLICommand("secretsmanager")
    public struct SecretsManager {
        /// AWS Secrets Manager get-secret-value command
        /// Example: aws secretsmanager get-secret-value --secret-id my-secret --profile prod --query SecretString --output text
        @CLICommand("get-secret-value")
        public struct GetSecretValue {
            /// Secret ID or ARN
            @Option public var secretId: String

            /// AWS profile to use
            @Option public var profile: String

            /// JMESPath query for filtering output
            @Option public var query: String?

            /// Output format
            @Option public var output: String?
        }

        /// AWS Secrets Manager list-secrets command
        /// Example: aws secretsmanager list-secrets --profile prod --output json
        @CLICommand("list-secrets")
        public struct ListSecrets {
            /// AWS profile to use
            @Option public var profile: String

            /// Output format
            @Option public var output: String?
        }
    }
}

// MARK: - Parsers

/// Parser for CloudFormation stack JSON output
public struct CloudFormationStackParser: CLIOutputParser {
    public init() {}

    public func parse(_ output: String) throws -> CloudFormationStack {
        guard let data = output.data(using: .utf8) else {
            throw CLIClientError.invalidOutput(reason: "Failed to convert CloudFormation output to data")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let stacks = json?["Stacks"] as? [[String: Any]],
              let stack = stacks.first else {
            throw CLIClientError.invalidOutput(reason: "Failed to parse CloudFormation stack")
        }

        let status = stack["StackStatus"] as? String ?? ""
        let outputs = (stack["Outputs"] as? [[String: Any]])?.compactMap { output -> CloudFormationStackOutput? in
            guard let key = output["OutputKey"] as? String,
                  let value = output["OutputValue"] as? String else {
                return nil
            }
            return CloudFormationStackOutput(
                key: key,
                value: value,
                description: output["Description"] as? String,
                exportName: output["ExportName"] as? String
            )
        } ?? []

        return CloudFormationStack(status: status, outputs: outputs)
    }
}

/// Parser for CloudFormation stack resources JSON output
public struct CloudFormationStackResourcesParser: CLIOutputParser {
    public init() {}

    public func parse(_ output: String) throws -> [CloudFormationStackResource] {
        guard let data = output.data(using: .utf8) else {
            throw CLIClientError.invalidOutput(reason: "Failed to convert CloudFormation output to data")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let resources = json?["StackResources"] as? [[String: Any]] else {
            throw CLIClientError.invalidOutput(reason: "Failed to parse CloudFormation stack resources")
        }

        return resources.compactMap { resource in
            guard let logicalId = resource["LogicalResourceId"] as? String,
                  let resourceType = resource["ResourceType"] as? String,
                  let resourceStatus = resource["ResourceStatus"] as? String else {
                return nil
            }
            return CloudFormationStackResource(
                logicalResourceId: logicalId,
                resourceType: resourceType,
                resourceStatus: resourceStatus
            )
        }
    }
}

// MARK: - Output Types

/// Parsed CloudFormation stack information
public struct CloudFormationStack: Sendable, Equatable {
    public let status: String
    public let outputs: [CloudFormationStackOutput]

    public init(status: String, outputs: [CloudFormationStackOutput]) {
        self.status = status
        self.outputs = outputs
    }

    /// Get output value by key
    public func output(forKey key: String) -> String? {
        outputs.first { $0.key == key }?.value
    }

    /// Convert outputs to dictionary
    public var outputsDictionary: [String: String] {
        Dictionary(uniqueKeysWithValues: outputs.map { ($0.key, $0.value) })
    }
}

/// CloudFormation stack output
public struct CloudFormationStackOutput: Sendable, Equatable {
    public let key: String
    public let value: String
    public let description: String?
    public let exportName: String?

    public init(key: String, value: String, description: String? = nil, exportName: String? = nil) {
        self.key = key
        self.value = value
        self.description = description
        self.exportName = exportName
    }
}

/// CloudFormation stack resource
public struct CloudFormationStackResource: Sendable, Equatable {
    public let logicalResourceId: String
    public let resourceType: String
    public let resourceStatus: String

    public init(logicalResourceId: String, resourceType: String, resourceStatus: String) {
        self.logicalResourceId = logicalResourceId
        self.resourceType = resourceType
        self.resourceStatus = resourceStatus
    }
}

// MARK: - Stack Events (Decodable for JSONOutputParser)

/// Response from describe-stack-events
public struct CloudFormationStackEventsResponse: Decodable, Sendable {
    public let StackEvents: [CloudFormationStackEvent]

    enum CodingKeys: String, CodingKey {
        case StackEvents
    }
}

/// CloudFormation stack event for tracking deployment progress
public struct CloudFormationStackEvent: Decodable, Sendable, Equatable, Identifiable {
    public let eventId: String
    public let stackName: String
    public let logicalResourceId: String
    public let resourceType: String
    public let resourceStatus: String
    public let resourceStatusReason: String?
    public let timestamp: Date

    public var id: String { eventId }

    enum CodingKeys: String, CodingKey {
        case eventId = "EventId"
        case stackName = "StackName"
        case logicalResourceId = "LogicalResourceId"
        case resourceType = "ResourceType"
        case resourceStatus = "ResourceStatus"
        case resourceStatusReason = "ResourceStatusReason"
        case timestamp = "Timestamp"
    }

    /// Whether this event represents an in-progress operation
    public var isInProgress: Bool {
        resourceStatus.contains("IN_PROGRESS")
    }

    /// Whether this event represents a completed operation
    public var isComplete: Bool {
        resourceStatus.contains("COMPLETE") && !resourceStatus.contains("CLEANUP")
    }

    /// Whether this event represents a failed operation
    public var isFailed: Bool {
        resourceStatus.contains("FAILED") || resourceStatus.contains("ROLLBACK")
    }

    /// A simplified display name for the resource
    public var displayName: String {
        // Simplify long CDK-generated names
        let parts = logicalResourceId.components(separatedBy: CharacterSet.alphanumerics.inverted)
        if parts.count > 3 {
            return parts.prefix(3).joined()
        }
        return logicalResourceId
    }

    /// A simplified resource type (e.g., "Lambda::Function" -> "Lambda Function")
    public var displayType: String {
        resourceType
            .replacingOccurrences(of: "AWS::", with: "")
            .replacingOccurrences(of: "::", with: " ")
    }
}
