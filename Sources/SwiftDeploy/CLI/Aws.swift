import CLIKit
import Foundation

/// AWS CLI program definition using macro-based API
@CLIProgram
public struct Aws {

    // MARK: - CloudFormation

    /// AWS CloudFormation describe-stacks command
    /// Example: aws cloudformation describe-stacks --stack-name MyStack --profile prod --output json
    @CLICommand("cloudformation describe-stacks")
    public struct CloudFormationDescribeStacks {
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
    @CLICommand("cloudformation describe-stack-resources")
    public struct CloudFormationDescribeStackResources {
        /// Stack name to describe
        @Option public var stackName: String

        /// AWS profile to use
        @Option public var profile: String

        /// Output format
        @Option public var output: String?
    }

    // MARK: - Lambda

    /// AWS Lambda update-function-code command
    /// Example: aws lambda update-function-code --function-name my-function --zip-file fileb://lambda.zip --profile prod
    @CLICommand("lambda update-function-code")
    public struct LambdaUpdateFunctionCode {
        /// Lambda function name
        @Option public var functionName: String

        /// Path to the zip file (should include fileb:// prefix)
        @Option public var zipFile: String

        /// AWS profile to use
        @Option public var profile: String
    }

    /// AWS Lambda get-function command
    /// Example: aws lambda get-function --function-name my-function --profile prod --output json
    @CLICommand("lambda get-function")
    public struct LambdaGetFunction {
        /// Lambda function name
        @Option public var functionName: String

        /// AWS profile to use
        @Option public var profile: String

        /// Output format
        @Option public var output: String?
    }

    // MARK: - CloudWatch Logs

    /// AWS Logs tail command
    /// Example: aws logs tail /aws/lambda/my-function --since 5m --format short --follow --profile prod
    @CLICommand("logs tail")
    public struct LogsTail {
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

    // MARK: - S3

    /// AWS S3 ls command
    /// Example: aws s3 ls s3://bucket-name/prefix --profile prod
    @CLICommand("s3 ls")
    public struct S3Ls {
        /// S3 path (e.g., s3://bucket-name/ or s3://bucket-name/prefix)
        @Positional public var path: String

        /// AWS profile to use
        @Option public var profile: String
    }

    /// AWS S3 cp command
    /// Example: aws s3 cp s3://bucket/file.txt ./file.txt --profile prod
    @CLICommand("s3 cp")
    public struct S3Cp {
        /// Source path (local or S3)
        @Positional public var source: String

        /// Destination path (local or S3)
        @Positional public var destination: String

        /// AWS profile to use
        @Option public var profile: String
    }

    // MARK: - Secrets Manager

    /// AWS Secrets Manager get-secret-value command
    /// Example: aws secretsmanager get-secret-value --secret-id my-secret --profile prod --query SecretString --output text
    @CLICommand("secretsmanager get-secret-value")
    public struct SecretsManagerGetSecretValue {
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
    @CLICommand("secretsmanager list-secrets")
    public struct SecretsManagerListSecrets {
        /// AWS profile to use
        @Option public var profile: String

        /// Output format
        @Option public var output: String?
    }
}

// MARK: - Parsers

/// Parser for CloudFormation stack JSON output
public struct CloudFormationStackParser: CLIOutputParser {
    public init() {}

    public func parse(_ output: String) throws -> CloudFormationStack {
        guard let data = output.data(using: .utf8) else {
            throw CLIServiceError.invalidOutput(reason: "Failed to convert CloudFormation output to data")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let stacks = json?["Stacks"] as? [[String: Any]],
              let stack = stacks.first else {
            throw CLIServiceError.invalidOutput(reason: "Failed to parse CloudFormation stack")
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
            throw CLIServiceError.invalidOutput(reason: "Failed to convert CloudFormation output to data")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let resources = json?["StackResources"] as? [[String: Any]] else {
            throw CLIServiceError.invalidOutput(reason: "Failed to parse CloudFormation stack resources")
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
