import ArgumentParser
import Foundation

/// Command for testing deployed AWS Lambda
struct TestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Test deployed AWS Lambda endpoints and infrastructure",
        subcommands: [
            FileEndpointCommand.self,
            FileEndpointVerboseCommand.self,
            VerifyS3Command.self,
            LogsCommand.self,
            AllCommand.self,
            GetUrlCommand.self
        ]
    )
}

// MARK: - Test Subcommands

extension TestCommand {
    /// Test S3 file endpoint
    struct FileEndpointCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "file",
            abstract: "Test S3 file upload/download endpoint"
        )

        @Option(name: .long, help: "AWS profile to use")
        var awsProfile: String = "production"

        func run() async throws {
            let service = AWSTestingService(awsProfile: awsProfile)
            try await service.testFileEndpoint()
        }
    }

    /// Test S3 file endpoint with verbose output
    struct FileEndpointVerboseCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "file-verbose",
            abstract: "Test S3 file endpoint with verbose curl output"
        )

        @Option(name: .long, help: "AWS profile to use")
        var awsProfile: String = "production"

        func run() async throws {
            let service = AWSTestingService(awsProfile: awsProfile)
            try await service.testFileEndpointVerbose()
        }
    }

    /// Verify S3 file was created
    struct VerifyS3Command: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "verify-s3",
            abstract: "Verify S3 file was created and show content"
        )

        @Option(name: .long, help: "AWS profile to use")
        var awsProfile: String = "production"

        func run() async throws {
            let service = AWSTestingService(awsProfile: awsProfile)
            try await service.verifyS3File()
        }
    }

    /// Check Lambda logs
    struct LogsCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "logs",
            abstract: "Show Lambda execution logs"
        )

        @Option(name: .long, help: "AWS profile to use")
        var awsProfile: String = "production"

        @Option(name: .long, help: "Time period (e.g., 5m, 1h, 30m)")
        var since: String = "5m"

        func run() async throws {
            let service = AWSTestingService(awsProfile: awsProfile)
            try await service.checkLogs(since: since)
        }
    }

    /// Run all deployment verification tests
    struct AllCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "all",
            abstract: "Run all deployment verification tests"
        )

        @Option(name: .long, help: "AWS profile to use")
        var awsProfile: String = "production"

        func run() async throws {
            let service = AWSTestingService(awsProfile: awsProfile)
            try await service.runAllTests()
        }
    }

    /// Get API Gateway URL
    struct GetUrlCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get-url",
            abstract: "Get API Gateway URL from CloudFormation"
        )

        @Option(name: .long, help: "AWS profile to use")
        var awsProfile: String = "production"

        func run() async throws {
            let service = AWSTestingService(awsProfile: awsProfile)
            let url = try await service.getApiGatewayUrl()
            print(url)
        }
    }
}
