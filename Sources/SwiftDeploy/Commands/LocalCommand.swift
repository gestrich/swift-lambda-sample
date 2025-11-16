import ArgumentParser
import Foundation

/// Command for managing local development environment
struct LocalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "local",
        abstract: "Manage local development environment (Docker services, testing)",
        subcommands: [
            StartServicesCommand.self,
            StopServicesCommand.self,
            StartDatabaseCommand.self,
            StopDatabaseCommand.self,
            StartS3Command.self,
            StopS3Command.self,
            SetupNetworkCommand.self,
            RunContainerCommand.self,
            TestCommand.self,
            CopyConfigCommand.self
        ]
    )
}

// MARK: - Service Management Commands

extension LocalCommand {
    /// Start all local services (PostgreSQL + MinIO)
    struct StartServicesCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-services",
            abstract: "Start all local services (PostgreSQL + MinIO)"
        )

        func run() async throws {
            let service = LocalDevelopmentService()
            try await service.stopAllServices()
            try await service.startS3()
            try await service.startDatabase()
        }
    }

    /// Stop all local services
    struct StopServicesCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop-services",
            abstract: "Stop all local services (PostgreSQL + MinIO)"
        )

        func run() async throws {
            let service = LocalDevelopmentService()
            try await service.stopAllServices()
        }
    }

    /// Start PostgreSQL database
    struct StartDatabaseCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-database",
            abstract: "Start local PostgreSQL database"
        )

        func run() async throws {
            let service = LocalDevelopmentService()
            try await service.startDatabase()
        }
    }

    /// Stop PostgreSQL database
    struct StopDatabaseCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop-database",
            abstract: "Stop local PostgreSQL database"
        )

        func run() async throws {
            let service = LocalDevelopmentService()
            try await service.stopDatabase()
        }
    }

    /// Start MinIO S3
    struct StartS3Command: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-s3",
            abstract: "Start local MinIO S3 service"
        )

        func run() async throws {
            let service = LocalDevelopmentService()
            try await service.startS3()
        }
    }

    /// Stop MinIO S3
    struct StopS3Command: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop-s3",
            abstract: "Stop local MinIO S3 service"
        )

        func run() async throws {
            let service = LocalDevelopmentService()
            try await service.stopS3()
        }
    }

    /// Setup Docker network for Lambda container
    struct SetupNetworkCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "setup-network",
            abstract: "Setup Docker network for local Lambda container testing"
        )

        func run() async throws {
            let service = LocalDevelopmentService()
            try await service.setupLambdaNetwork()
        }
    }

    /// Run Lambda in interactive Linux container
    struct RunContainerCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run-container",
            abstract: "Run Lambda in interactive Linux container"
        )

        func run() async throws {
            let service = LocalDevelopmentService()
            try await service.runLambdaContainer()
        }
    }

    /// Test local Lambda
    struct TestCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test",
            abstract: "Test local Lambda endpoints"
        )

        @Option(name: .long, help: "Port to test (default: 8080)")
        var port: Int = 8080

        func run() async throws {
            let service = LocalDevelopmentService()
            try await service.testLocalLambda(port: port)
        }
    }

    /// Copy config file
    struct CopyConfigCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "copy-config",
            abstract: "Copy config file to ~/.swiftSampleDemo/"
        )

        func run() async throws {
            let service = LocalDevelopmentService()
            try await service.copyConfig()
        }
    }
}
