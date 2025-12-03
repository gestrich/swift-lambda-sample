import ArgumentParser
import Foundation
import SwiftDeploy

/// Top-level command for all AWS operations
struct AWSCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aws",
        abstract: "AWS deployment and management operations",
        subcommands: [
            DeployInitCommand.self,
            DeployCommand.self,
            UpdateLambdaCommand.self,
            TearDownCommand.self,
            StatusCommand.self,
            LogsCommand.self,
            GetUrlCommand.self,
            TestCommand.self
        ]
    )
}

// MARK: - AWS Subcommands

extension AWSCommand {
    /// Show Lambda CloudWatch logs
    struct LogsCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "logs",
            abstract: "Show Lambda execution logs"
        )

        @Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
        var awsProfile: String?

        @Option(name: .long, help: "Use aws-vault for credential management")
        var useAwsVault: Bool?

        @Option(name: .long, help: "Time period (e.g., 5m, 1h, 30m)")
        var since: String = "5m"

        func run() async throws {
            let awsConfig = try AWSAuthConfiguration.resolve(
                profileName: awsProfile,
                useAWSVault: useAwsVault
            )
            let service = AWSTestingService(awsConfig: awsConfig, cliService: .shared)
            try await service.checkLogs(since: since)
        }
    }

    /// Get API Gateway URL
    struct GetUrlCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get-url",
            abstract: "Get API Gateway URL from CloudFormation"
        )

        @Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
        var awsProfile: String?

        @Option(name: .long, help: "Use aws-vault for credential management")
        var useAwsVault: Bool?

        func run() async throws {
            let awsConfig = try AWSAuthConfiguration.resolve(
                profileName: awsProfile,
                useAWSVault: useAwsVault
            )
            let service = AWSTestingService(awsConfig: awsConfig, cliService: .shared)
            let url = try await service.getApiGatewayUrl()
            print(url)
        }
    }

    /// Test deployed AWS Lambda endpoints
    struct TestCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test",
            abstract: "Test deployed AWS Lambda endpoints",
            subcommands: [
                AllCommand.self,
                S3UploadCommand.self,
                UsersCommand.self
            ]
        )
    }
}

// MARK: - Test Subcommands

extension AWSCommand.TestCommand {
    /// Run all deployment verification tests
    struct AllCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "all",
            abstract: "Run all deployment verification tests"
        )

        @Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
        var awsProfile: String?

        @Option(name: .long, help: "Use aws-vault for credential management")
        var useAwsVault: Bool?

        func run() async throws {
            let awsConfig = try AWSAuthConfiguration.resolve(
                profileName: awsProfile,
                useAWSVault: useAwsVault
            )
            let service = AWSTestingService(awsConfig: awsConfig, cliService: .shared)
            try await service.runAllTests()
        }
    }

    /// Test S3 file upload/download endpoint
    struct S3UploadCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "s3-upload",
            abstract: "Test S3 file upload/download endpoint"
        )

        @Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
        var awsProfile: String?

        @Option(name: .long, help: "Use aws-vault for credential management")
        var useAwsVault: Bool?

        @Flag(name: .long, help: "Show verbose curl output")
        var verbose: Bool = false

        func run() async throws {
            let awsConfig = try AWSAuthConfiguration.resolve(
                profileName: awsProfile,
                useAWSVault: useAwsVault
            )
            let service = AWSTestingService(awsConfig: awsConfig, cliService: .shared)

            if verbose {
                try await service.testFileEndpointVerbose()
            } else {
                try await service.testFileEndpoint()
            }

            // Also verify S3 file was created
            try await service.verifyS3File()
        }
    }

    /// Test user CRUD endpoints (requires PostgreSQL)
    struct UsersCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "users",
            abstract: "Test user CRUD endpoints (requires PostgreSQL deployment)"
        )

        @Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
        var awsProfile: String?

        @Option(name: .long, help: "Use aws-vault for credential management")
        var useAwsVault: Bool?

        func run() async throws {
            let awsConfig = try AWSAuthConfiguration.resolve(
                profileName: awsProfile,
                useAWSVault: useAwsVault
            )
            let service = AWSTestingService(awsConfig: awsConfig, cliService: .shared)
            try await service.testUserEndpoints()
        }
    }
}
