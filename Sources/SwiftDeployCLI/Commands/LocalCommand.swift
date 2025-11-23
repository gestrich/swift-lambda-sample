import ArgumentParser
import Foundation
import SwiftDeploy

/// Top-level command for local development operations
struct LocalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "local",
        abstract: "Local development environment management",
        subcommands: [
            ServicesCommand.self,
            LambdaCommand.self,
            CopyConfigCommand.self
        ]
    )
}

// MARK: - Services Management

extension LocalCommand {
    /// Manage local development services (PostgreSQL + MinIO)
    struct ServicesCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "services",
            abstract: "Manage local development services (PostgreSQL + MinIO)",
            subcommands: [
                StartAllCommand.self,
                StopAllCommand.self,
                StartDatabaseCommand.self,
                StopDatabaseCommand.self,
                StartS3Command.self,
                StopS3Command.self
            ]
        )
    }
}

// MARK: - Services Subcommands

extension LocalCommand.ServicesCommand {
    /// Start all local services (PostgreSQL + MinIO)
    struct StartAllCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-all",
            abstract: "Start all local services (PostgreSQL + MinIO)"
        )

        func run() async throws {
            let service = LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.stopAllServices()
            try await service.startS3()
            try await service.startDatabase()
        }
    }

    /// Stop all local services
    struct StopAllCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop-all",
            abstract: "Stop all local services (PostgreSQL + MinIO)"
        )

        func run() async throws {
            let service = LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
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
            let service = LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
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
            let service = LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
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
            let service = LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
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
            let service = LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.stopS3()
        }
    }
}

// MARK: - Lambda Container Testing

extension LocalCommand {
    /// Lambda container testing and management
    struct LambdaCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "lambda",
            abstract: "Lambda container testing and management",
            subcommands: [
                SetupNetworkCommand.self,
                BuildCommand.self,
                StartCommand.self,
                StopCommand.self,
                RunContainerCommand.self,
                TestCommand.self
            ]
        )
    }
}

// MARK: - Lambda Subcommands

extension LocalCommand.LambdaCommand {
    /// Setup Docker network for Lambda container
    struct SetupNetworkCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "setup-network",
            abstract: "Setup Docker network for local Lambda container testing"
        )

        func run() async throws {
            let service = LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.setupLambdaNetwork()
        }
    }

    /// Build Lambda for Linux
    struct BuildCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "build",
            abstract: "Build Lambda for Linux (AMD64)"
        )

        @Flag(name: .long, help: "Clean build artifacts before building")
        var clean: Bool = false

        func run() async throws {
            let service = LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.buildLambda(clean: clean)
        }
    }

    /// Start Lambda locally in background
    struct StartCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start",
            abstract: "Start Lambda locally in background"
        )

        func run() async throws {
            let service = LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.startLambdaLocally()
        }
    }

    /// Stop Lambda
    struct StopCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop",
            abstract: "Stop Lambda process"
        )

        func run() async throws {
            let service = LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.stopLambdaLocally()
        }
    }

    /// Run Lambda in interactive Linux container
    struct RunContainerCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run-container",
            abstract: "Run Lambda in interactive Linux container"
        )

        func run() async throws {
            let service = LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.runLambdaContainer()
        }
    }

    /// Test local Lambda
    struct TestCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test",
            abstract: "Test local Lambda endpoints"
        )

        func run() async throws {
            let service = LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.testLocalLambda()
        }
    }
}

// MARK: - Configuration Management

extension LocalCommand {
    /// Copy config file
    struct CopyConfigCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "copy-config",
            abstract: "Copy runtime config file to ~/.swiftSampleDemo/"
        )

        func run() async throws {
            let service = LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.copyConfig()
        }
    }
}
