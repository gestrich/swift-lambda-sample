import d_sdk_aws
import CLISDK
@testable import c_service_deploy_remote
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

    @Test("CloudFormation.DescribeStacks commandPath")
    func testCommandPath() {
        #expect(Aws.CloudFormation.DescribeStacks.commandPath == ["cloudformation", "describe-stacks"])
    }

    @Test("CloudFormation.DescribeStacks minimal command line")
    func testMinimalCommandLine() {
        let cmd = Aws.CloudFormation.DescribeStacks(stackName: "MyStack", profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "cloudformation", "describe-stacks",
            "--stack-name", "MyStack",
            "--profile", "prod"
        ])
    }

    @Test("CloudFormation.DescribeStacks with output format")
    func testWithOutputFormat() {
        let cmd = Aws.CloudFormation.DescribeStacks(
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

    @Test("CloudFormation.DescribeStacks with query")
    func testWithQuery() {
        let cmd = Aws.CloudFormation.DescribeStacks(
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

    @Test("CloudFormation.DescribeStacks command string")
    func testCommandString() {
        let cmd = Aws.CloudFormation.DescribeStacks(stackName: "MyStack", profile: "prod")
        #expect(cmd.commandString == "aws cloudformation describe-stacks --stack-name MyStack --profile prod")
    }
}

@Suite("CloudFormation DescribeStackResources Tests")
struct CloudFormationDescribeStackResourcesTests {

    @Test("CloudFormation.DescribeStackResources commandPath")
    func testCommandPath() {
        #expect(Aws.CloudFormation.DescribeStackResources.commandPath == ["cloudformation", "describe-stack-resources"])
    }

    @Test("CloudFormation.DescribeStackResources minimal command line")
    func testMinimalCommandLine() {
        let cmd = Aws.CloudFormation.DescribeStackResources(stackName: "MyStack", profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "cloudformation", "describe-stack-resources",
            "--stack-name", "MyStack",
            "--profile", "prod"
        ])
    }

    @Test("CloudFormation.DescribeStackResources with output format")
    func testWithOutputFormat() {
        let cmd = Aws.CloudFormation.DescribeStackResources(
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

    @Test("Lambda.UpdateFunctionCode commandPath")
    func testCommandPath() {
        #expect(Aws.Lambda.UpdateFunctionCode.commandPath == ["lambda", "update-function-code"])
    }

    @Test("Lambda.UpdateFunctionCode command line")
    func testCommandLine() {
        let cmd = Aws.Lambda.UpdateFunctionCode(
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

    @Test("Lambda.UpdateFunctionCode command string")
    func testCommandString() {
        let cmd = Aws.Lambda.UpdateFunctionCode(
            functionName: "my-lambda",
            zipFile: "fileb://lambda.zip",
            profile: "prod"
        )
        #expect(cmd.commandString == "aws lambda update-function-code --function-name my-lambda --zip-file fileb://lambda.zip --profile prod")
    }
}

@Suite("Lambda GetFunction Tests")
struct LambdaGetFunctionTests {

    @Test("Lambda.GetFunction commandPath")
    func testCommandPath() {
        #expect(Aws.Lambda.GetFunction.commandPath == ["lambda", "get-function"])
    }

    @Test("Lambda.GetFunction minimal command line")
    func testMinimalCommandLine() {
        let cmd = Aws.Lambda.GetFunction(functionName: "my-lambda", profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "lambda", "get-function",
            "--function-name", "my-lambda",
            "--profile", "prod"
        ])
    }

    @Test("Lambda.GetFunction with output format")
    func testWithOutputFormat() {
        let cmd = Aws.Lambda.GetFunction(
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

    @Test("Logs.Tail commandPath")
    func testCommandPath() {
        #expect(Aws.Logs.Tail.commandPath == ["logs", "tail"])
    }

    @Test("Logs.Tail minimal command line")
    func testMinimalCommandLine() {
        let cmd = Aws.Logs.Tail(logGroup: "/aws/lambda/my-function", profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "logs", "tail",
            "/aws/lambda/my-function",
            "--profile", "prod"
        ])
    }

    @Test("Logs.Tail with since option")
    func testWithSince() {
        let cmd = Aws.Logs.Tail(
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

    @Test("Logs.Tail with format option")
    func testWithFormat() {
        let cmd = Aws.Logs.Tail(
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

    @Test("Logs.Tail with follow flag")
    func testWithFollow() {
        let cmd = Aws.Logs.Tail(
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

    @Test("S3.Ls commandPath")
    func testCommandPath() {
        #expect(Aws.S3.Ls.commandPath == ["s3", "ls"])
    }

    @Test("S3.Ls command line")
    func testCommandLine() {
        let cmd = Aws.S3.Ls(path: "s3://my-bucket/", profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "s3", "ls",
            "s3://my-bucket/",
            "--profile", "prod"
        ])
    }

    @Test("S3.Ls with prefix")
    func testWithPrefix() {
        let cmd = Aws.S3.Ls(path: "s3://my-bucket/folder/", profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "s3", "ls",
            "s3://my-bucket/folder/",
            "--profile", "prod"
        ])
    }
}

@Suite("S3 Cp Tests")
struct S3CpTests {

    @Test("S3.Cp commandPath")
    func testCommandPath() {
        #expect(Aws.S3.Cp.commandPath == ["s3", "cp"])
    }

    @Test("S3.Cp download command line")
    func testDownloadCommandLine() {
        let cmd = Aws.S3.Cp(
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

    @Test("S3.Cp upload command line")
    func testUploadCommandLine() {
        let cmd = Aws.S3.Cp(
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

    @Test("S3.Cp to stdout")
    func testToStdout() {
        let cmd = Aws.S3.Cp(
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

    @Test("SecretsManager.GetSecretValue commandPath")
    func testCommandPath() {
        #expect(Aws.SecretsManager.GetSecretValue.commandPath == ["secretsmanager", "get-secret-value"])
    }

    @Test("SecretsManager.GetSecretValue minimal command line")
    func testMinimalCommandLine() {
        let cmd = Aws.SecretsManager.GetSecretValue(secretId: "my-secret", profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "secretsmanager", "get-secret-value",
            "--secret-id", "my-secret",
            "--profile", "prod"
        ])
    }

    @Test("SecretsManager.GetSecretValue with query and output")
    func testWithQueryAndOutput() {
        let cmd = Aws.SecretsManager.GetSecretValue(
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

    @Test("SecretsManager.ListSecrets commandPath")
    func testCommandPath() {
        #expect(Aws.SecretsManager.ListSecrets.commandPath == ["secretsmanager", "list-secrets"])
    }

    @Test("SecretsManager.ListSecrets minimal command line")
    func testMinimalCommandLine() {
        let cmd = Aws.SecretsManager.ListSecrets(profile: "prod")
        #expect(cmd.commandLine == [
            "aws", "secretsmanager", "list-secrets",
            "--profile", "prod"
        ])
    }

    @Test("SecretsManager.ListSecrets with output format")
    func testWithOutputFormat() {
        let cmd = Aws.SecretsManager.ListSecrets(profile: "prod", output: "json")
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
        #expect(throws: CLIClientError.self) {
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
        #expect(throws: CLIClientError.self) {
            try parser.parse(json)
        }
    }
}
