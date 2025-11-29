import CLIKit
@testable import SwiftDeploy
import Testing

@Suite("AWS CLI Command Tests")
struct AWSCLITests {

    @Test("Aws program name")
    func testProgramName() {
        #expect(Aws.programName == "aws")
    }
}

// MARK: - CloudFormation Commands

@Suite("CloudFormation DescribeStacks Tests")
struct CloudFormationDescribeStacksTests {

    @Test("CloudFormationDescribeStacks command name")
    func testCommandName() {
        #expect(Aws.CloudFormationDescribeStacks.commandName == "cloudformation describe-stacks")
    }

    @Test("CloudFormationDescribeStacks minimal command line")
    func testMinimalCommandLine() {
        let cmd = Aws.CloudFormationDescribeStacks(stackName: "MyStack", profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "cloudformation", "describe-stacks",
            "--stack-name", "MyStack",
            "--profile", "prod"
        ])
    }

    @Test("CloudFormationDescribeStacks with output format")
    func testWithOutputFormat() {
        let cmd = Aws.CloudFormationDescribeStacks(
            stackName: "MyStack",
            profile: "prod",
            output: "json"
        )
        #expect(cmd.commandLine == [
            "aws", "cloudformation", "describe-stacks",
            "--stack-name", "MyStack",
            "--profile", "prod",
            "--output", "json"
        ])
    }

    @Test("CloudFormationDescribeStacks with query")
    func testWithQuery() {
        let cmd = Aws.CloudFormationDescribeStacks(
            stackName: "MyStack",
            profile: "prod",
            output: "text",
            query: "Stacks[0].StackStatus"
        )
        #expect(cmd.commandLine == [
            "aws", "cloudformation", "describe-stacks",
            "--stack-name", "MyStack",
            "--profile", "prod",
            "--output", "text",
            "--query", "Stacks[0].StackStatus"
        ])
    }

    @Test("CloudFormationDescribeStacks command string")
    func testCommandString() {
        let cmd = Aws.CloudFormationDescribeStacks(stackName: "MyStack", profile: "prod")
        #expect(cmd.commandString == "aws cloudformation describe-stacks --stack-name MyStack --profile prod")
    }
}

@Suite("CloudFormation DescribeStackResources Tests")
struct CloudFormationDescribeStackResourcesTests {

    @Test("CloudFormationDescribeStackResources command name")
    func testCommandName() {
        #expect(Aws.CloudFormationDescribeStackResources.commandName == "cloudformation describe-stack-resources")
    }

    @Test("CloudFormationDescribeStackResources minimal command line")
    func testMinimalCommandLine() {
        let cmd = Aws.CloudFormationDescribeStackResources(stackName: "MyStack", profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "cloudformation", "describe-stack-resources",
            "--stack-name", "MyStack",
            "--profile", "prod"
        ])
    }

    @Test("CloudFormationDescribeStackResources with output format")
    func testWithOutputFormat() {
        let cmd = Aws.CloudFormationDescribeStackResources(
            stackName: "MyStack",
            profile: "prod",
            output: "json"
        )
        #expect(cmd.commandLine == [
            "aws", "cloudformation", "describe-stack-resources",
            "--stack-name", "MyStack",
            "--profile", "prod",
            "--output", "json"
        ])
    }
}

// MARK: - Lambda Commands

@Suite("Lambda UpdateFunctionCode Tests")
struct LambdaUpdateFunctionCodeTests {

    @Test("LambdaUpdateFunctionCode command name")
    func testCommandName() {
        #expect(Aws.LambdaUpdateFunctionCode.commandName == "lambda update-function-code")
    }

    @Test("LambdaUpdateFunctionCode command line")
    func testCommandLine() {
        let cmd = Aws.LambdaUpdateFunctionCode(
            functionName: "my-lambda",
            zipFile: "fileb://lambda.zip",
            profile: "prod"
        )
        #expect(cmd.commandLine == [
            "aws", "lambda", "update-function-code",
            "--function-name", "my-lambda",
            "--zip-file", "fileb://lambda.zip",
            "--profile", "prod"
        ])
    }

    @Test("LambdaUpdateFunctionCode command string")
    func testCommandString() {
        let cmd = Aws.LambdaUpdateFunctionCode(
            functionName: "my-lambda",
            zipFile: "fileb://lambda.zip",
            profile: "prod"
        )
        #expect(cmd.commandString == "aws lambda update-function-code --function-name my-lambda --zip-file fileb://lambda.zip --profile prod")
    }
}

@Suite("Lambda GetFunction Tests")
struct LambdaGetFunctionTests {

    @Test("LambdaGetFunction command name")
    func testCommandName() {
        #expect(Aws.LambdaGetFunction.commandName == "lambda get-function")
    }

    @Test("LambdaGetFunction minimal command line")
    func testMinimalCommandLine() {
        let cmd = Aws.LambdaGetFunction(functionName: "my-lambda", profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "lambda", "get-function",
            "--function-name", "my-lambda",
            "--profile", "prod"
        ])
    }

    @Test("LambdaGetFunction with output format")
    func testWithOutputFormat() {
        let cmd = Aws.LambdaGetFunction(
            functionName: "my-lambda",
            profile: "prod",
            output: "json"
        )
        #expect(cmd.commandLine == [
            "aws", "lambda", "get-function",
            "--function-name", "my-lambda",
            "--profile", "prod",
            "--output", "json"
        ])
    }
}

// MARK: - CloudWatch Logs Commands

@Suite("Logs Tail Tests")
struct LogsTailTests {

    @Test("LogsTail command name")
    func testCommandName() {
        #expect(Aws.LogsTail.commandName == "logs tail")
    }

    @Test("LogsTail minimal command line")
    func testMinimalCommandLine() {
        let cmd = Aws.LogsTail(logGroup: "/aws/lambda/my-function", profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "logs", "tail",
            "/aws/lambda/my-function",
            "--profile", "prod"
        ])
    }

    @Test("LogsTail with since option")
    func testWithSince() {
        let cmd = Aws.LogsTail(
            logGroup: "/aws/lambda/my-function",
            since: "5m",
            profile: "prod"
        )
        #expect(cmd.commandLine == [
            "aws", "logs", "tail",
            "/aws/lambda/my-function",
            "--since", "5m",
            "--profile", "prod"
        ])
    }

    @Test("LogsTail with format option")
    func testWithFormat() {
        let cmd = Aws.LogsTail(
            logGroup: "/aws/lambda/my-function",
            since: "1h",
            format: "short",
            profile: "prod"
        )
        #expect(cmd.commandLine == [
            "aws", "logs", "tail",
            "/aws/lambda/my-function",
            "--since", "1h",
            "--format", "short",
            "--profile", "prod"
        ])
    }

    @Test("LogsTail with follow flag")
    func testWithFollow() {
        let cmd = Aws.LogsTail(
            logGroup: "/aws/lambda/my-function",
            since: "5m",
            format: "short",
            follow: true,
            profile: "prod"
        )
        #expect(cmd.commandLine == [
            "aws", "logs", "tail",
            "/aws/lambda/my-function",
            "--since", "5m",
            "--format", "short",
            "--follow",
            "--profile", "prod"
        ])
    }
}

// MARK: - S3 Commands

@Suite("S3 Ls Tests")
struct S3LsTests {

    @Test("S3Ls command name")
    func testCommandName() {
        #expect(Aws.S3Ls.commandName == "s3 ls")
    }

    @Test("S3Ls command line")
    func testCommandLine() {
        let cmd = Aws.S3Ls(path: "s3://my-bucket/", profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "s3", "ls",
            "s3://my-bucket/",
            "--profile", "prod"
        ])
    }

    @Test("S3Ls with prefix")
    func testWithPrefix() {
        let cmd = Aws.S3Ls(path: "s3://my-bucket/folder/", profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "s3", "ls",
            "s3://my-bucket/folder/",
            "--profile", "prod"
        ])
    }
}

@Suite("S3 Cp Tests")
struct S3CpTests {

    @Test("S3Cp command name")
    func testCommandName() {
        #expect(Aws.S3Cp.commandName == "s3 cp")
    }

    @Test("S3Cp download command line")
    func testDownloadCommandLine() {
        let cmd = Aws.S3Cp(
            source: "s3://my-bucket/file.txt",
            destination: "./file.txt",
            profile: "prod"
        )
        #expect(cmd.commandLine == [
            "aws", "s3", "cp",
            "s3://my-bucket/file.txt",
            "./file.txt",
            "--profile", "prod"
        ])
    }

    @Test("S3Cp upload command line")
    func testUploadCommandLine() {
        let cmd = Aws.S3Cp(
            source: "./local-file.txt",
            destination: "s3://my-bucket/remote-file.txt",
            profile: "prod"
        )
        #expect(cmd.commandLine == [
            "aws", "s3", "cp",
            "./local-file.txt",
            "s3://my-bucket/remote-file.txt",
            "--profile", "prod"
        ])
    }

    @Test("S3Cp to stdout")
    func testToStdout() {
        let cmd = Aws.S3Cp(
            source: "s3://my-bucket/file.txt",
            destination: "-",
            profile: "prod"
        )
        #expect(cmd.commandLine == [
            "aws", "s3", "cp",
            "s3://my-bucket/file.txt",
            "-",
            "--profile", "prod"
        ])
    }
}

// MARK: - Secrets Manager Commands

@Suite("SecretsManager GetSecretValue Tests")
struct SecretsManagerGetSecretValueTests {

    @Test("SecretsManagerGetSecretValue command name")
    func testCommandName() {
        #expect(Aws.SecretsManagerGetSecretValue.commandName == "secretsmanager get-secret-value")
    }

    @Test("SecretsManagerGetSecretValue minimal command line")
    func testMinimalCommandLine() {
        let cmd = Aws.SecretsManagerGetSecretValue(secretId: "my-secret", profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "secretsmanager", "get-secret-value",
            "--secret-id", "my-secret",
            "--profile", "prod"
        ])
    }

    @Test("SecretsManagerGetSecretValue with query and output")
    func testWithQueryAndOutput() {
        let cmd = Aws.SecretsManagerGetSecretValue(
            secretId: "my-secret",
            profile: "prod",
            query: "SecretString",
            output: "text"
        )
        #expect(cmd.commandLine == [
            "aws", "secretsmanager", "get-secret-value",
            "--secret-id", "my-secret",
            "--profile", "prod",
            "--query", "SecretString",
            "--output", "text"
        ])
    }
}

@Suite("SecretsManager ListSecrets Tests")
struct SecretsManagerListSecretsTests {

    @Test("SecretsManagerListSecrets command name")
    func testCommandName() {
        #expect(Aws.SecretsManagerListSecrets.commandName == "secretsmanager list-secrets")
    }

    @Test("SecretsManagerListSecrets minimal command line")
    func testMinimalCommandLine() {
        let cmd = Aws.SecretsManagerListSecrets(profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "secretsmanager", "list-secrets",
            "--profile", "prod"
        ])
    }

    @Test("SecretsManagerListSecrets with output format")
    func testWithOutputFormat() {
        let cmd = Aws.SecretsManagerListSecrets(profile: "prod", output: "json")
        #expect(cmd.commandLine == [
            "aws", "secretsmanager", "list-secrets",
            "--profile", "prod",
            "--output", "json"
        ])
    }
}

// MARK: - Parser Tests

@Suite("CloudFormation Stack Parser Tests")
struct CloudFormationStackParserTests {

    @Test("Parse valid CloudFormation stack output")
    func testParseValidStack() throws {
        let json = """
        {
            "Stacks": [{
                "StackStatus": "CREATE_COMPLETE",
                "Outputs": [
                    {
                        "OutputKey": "ApiGatewayUrl",
                        "OutputValue": "https://api.example.com",
                        "Description": "API Gateway URL"
                    },
                    {
                        "OutputKey": "BucketName",
                        "OutputValue": "my-bucket-123"
                    }
                ]
            }]
        }
        """
        let parser = CloudFormationStackParser()
        let result = try parser.parse(json)

        #expect(result.status == "CREATE_COMPLETE")
        #expect(result.outputs.count == 2)
        #expect(result.output(forKey: "ApiGatewayUrl") == "https://api.example.com")
        #expect(result.output(forKey: "BucketName") == "my-bucket-123")
        #expect(result.outputsDictionary["ApiGatewayUrl"] == "https://api.example.com")
    }

    @Test("Parse stack with empty outputs")
    func testParseStackEmptyOutputs() throws {
        let json = """
        {
            "Stacks": [{
                "StackStatus": "UPDATE_IN_PROGRESS",
                "Outputs": []
            }]
        }
        """
        let parser = CloudFormationStackParser()
        let result = try parser.parse(json)

        #expect(result.status == "UPDATE_IN_PROGRESS")
        #expect(result.outputs.isEmpty)
    }

    @Test("Parse stack without outputs key")
    func testParseStackNoOutputs() throws {
        let json = """
        {
            "Stacks": [{
                "StackStatus": "DELETE_IN_PROGRESS"
            }]
        }
        """
        let parser = CloudFormationStackParser()
        let result = try parser.parse(json)

        #expect(result.status == "DELETE_IN_PROGRESS")
        #expect(result.outputs.isEmpty)
    }

    @Test("Parse throws on invalid JSON")
    func testParseInvalidJson() {
        let parser = CloudFormationStackParser()
        #expect(throws: (any Error).self) {
            try parser.parse("not valid json")
        }
    }

    @Test("Parse throws on missing stacks")
    func testParseMissingStacks() {
        let json = """
        {
            "Stacks": []
        }
        """
        let parser = CloudFormationStackParser()
        #expect(throws: CLIServiceError.self) {
            try parser.parse(json)
        }
    }
}

@Suite("CloudFormation Stack Resources Parser Tests")
struct CloudFormationStackResourcesParserTests {

    @Test("Parse valid stack resources")
    func testParseValidResources() throws {
        let json = """
        {
            "StackResources": [
                {
                    "LogicalResourceId": "MyLambda",
                    "ResourceType": "AWS::Lambda::Function",
                    "ResourceStatus": "CREATE_COMPLETE"
                },
                {
                    "LogicalResourceId": "MyBucket",
                    "ResourceType": "AWS::S3::Bucket",
                    "ResourceStatus": "CREATE_COMPLETE"
                }
            ]
        }
        """
        let parser = CloudFormationStackResourcesParser()
        let result = try parser.parse(json)

        #expect(result.count == 2)
        #expect(result[0].logicalResourceId == "MyLambda")
        #expect(result[0].resourceType == "AWS::Lambda::Function")
        #expect(result[0].resourceStatus == "CREATE_COMPLETE")
        #expect(result[1].logicalResourceId == "MyBucket")
    }

    @Test("Parse empty resources")
    func testParseEmptyResources() throws {
        let json = """
        {
            "StackResources": []
        }
        """
        let parser = CloudFormationStackResourcesParser()
        let result = try parser.parse(json)

        #expect(result.isEmpty)
    }

    @Test("Parse throws on invalid JSON")
    func testParseInvalidJson() {
        let parser = CloudFormationStackResourcesParser()
        #expect(throws: (any Error).self) {
            try parser.parse("invalid")
        }
    }

    @Test("Parse throws on missing StackResources")
    func testParseMissingResources() {
        let json = """
        {
            "OtherKey": []
        }
        """
        let parser = CloudFormationStackResourcesParser()
        #expect(throws: CLIServiceError.self) {
            try parser.parse(json)
        }
    }
}
