import ArgumentParser
import Foundation
import SwiftDeploy

// MARK: - Local Mac Command (Native macOS)

/// Native macOS development workflow (fast iteration)
struct LocalMacCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "local-mac",
        abstract: "Native macOS development workflow (fast iteration)",
        subcommands: [
            BuildCommand.self,
            CopyConfigCommand.self,
            StartAllCommand.self,
            StartCommand.self,
            StartDatabaseCommand.self,
            StartDynamoDBCommand.self,
            StartS3Command.self,
            StatusCommand.self,
            StopAllCommand.self,
            StopCommand.self,
            StopDatabaseCommand.self,
            StopDynamoDBCommand.self,
            StopS3Command.self,
            TestCommand.self
        ]
    )
}

// MARK: - Local Mac Subcommands

extension LocalMacCommand {
    /// Build Lambda for macOS (native)
    struct BuildCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "build",
            abstract: "Build Lambda for macOS (native Swift build)"
        )

        @Flag(name: .long, help: "Clean build artifacts before building")
        var clean: Bool = false

        func run() async throws {
            let service = XcodeLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.build(clean: clean)
        }
    }

    /// Start Lambda locally (native process)
    struct StartCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start",
            abstract: "Start Lambda locally (native process)"
        )

        func run() async throws {
            let service = XcodeLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.startLambda()
        }
    }

    /// Stop Lambda (native process)
    struct StopCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop",
            abstract: "Stop Lambda (native process)"
        )

        func run() async throws {
            let service = XcodeLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.stopLambda()
        }
    }

    /// Start Lambda with all services (native process)
    struct StartAllCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-all",
            abstract: "Start Lambda with services (PostgreSQL + MinIO + native Lambda)"
        )

        func run() async throws {
            let service = XcodeLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.startWithServices()
        }
    }

    /// Stop Lambda and all services
    struct StopAllCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop-all",
            abstract: "Stop Lambda and all services"
        )

        func run() async throws {
            let service = XcodeLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.stopWithServices()
        }
    }

    /// Start PostgreSQL database
    struct StartDatabaseCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-database",
            abstract: "Start local PostgreSQL database"
        )

        func run() async throws {
            let service = XcodeLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
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
            let service = XcodeLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.stopDatabase()
        }
    }

    /// Start DynamoDB Local
    struct StartDynamoDBCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-dynamodb",
            abstract: "Start local DynamoDB"
        )

        func run() async throws {
            let service = XcodeLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.startDynamoDB()
        }
    }

    /// Stop DynamoDB Local
    struct StopDynamoDBCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop-dynamodb",
            abstract: "Stop local DynamoDB"
        )

        func run() async throws {
            let service = XcodeLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.stopDynamoDB()
        }
    }

    /// Start MinIO S3
    struct StartS3Command: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-s3",
            abstract: "Start local MinIO S3 service"
        )

        func run() async throws {
            let service = XcodeLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
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
            let service = XcodeLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.stopS3()
        }
    }

    /// Test local Lambda
    struct TestCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test",
            abstract: "Test local Lambda endpoints"
        )

        func run() async throws {
            let service = XcodeLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.testLambda()
        }
    }

    /// Show status of all services
    struct StatusCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show status of Lambda and services (PostgreSQL + MinIO)"
        )

        func run() async throws {
            let service = XcodeLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            let status = try await service.status()
            printStatus(status, mode: "Mac (Native)")
        }
    }

    /// Copy config file
    struct CopyConfigCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "copy-config",
            abstract: "Copy runtime config file to ~/.swiftSampleDemo/"
        )

        func run() async throws {
            let service = XcodeLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.copyConfig()
        }
    }
}

// MARK: - Local Linux Command (Container)

/// Linux container deployment workflow (AWS Lambda compatible)
struct LocalLinuxCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "local-linux",
        abstract: "Linux container deployment workflow (AWS Lambda compatible)",
        subcommands: [
            BuildCommand.self,
            CopyConfigCommand.self,
            RunInteractiveCommand.self,
            SetupNetworkCommand.self,
            StartAllCommand.self,
            StartCommand.self,
            StartDatabaseCommand.self,
            StartDynamoDBCommand.self,
            StartS3Command.self,
            StatusCommand.self,
            StopAllCommand.self,
            StopCommand.self,
            StopDatabaseCommand.self,
            StopDynamoDBCommand.self,
            StopS3Command.self,
            TestCommand.self
        ]
    )
}

// MARK: - Local Linux Subcommands

extension LocalLinuxCommand {
    /// Build Lambda for Linux (Docker-based)
    struct BuildCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "build",
            abstract: "Build Lambda for Linux (AMD64, Docker-based)"
        )

        @Flag(name: .long, help: "Clean build artifacts before building")
        var clean: Bool = false

        func run() async throws {
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.build(clean: clean)
        }
    }

    /// Start Lambda container
    struct StartCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start",
            abstract: "Start Lambda container"
        )

        func run() async throws {
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.startLambda()
        }
    }

    /// Stop Lambda container
    struct StopCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop",
            abstract: "Stop Lambda container"
        )

        func run() async throws {
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.stopLambda()
        }
    }

    /// Start Lambda container with all services
    struct StartAllCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-all",
            abstract: "Start Lambda with services (PostgreSQL + MinIO + container)"
        )

        func run() async throws {
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.startWithServices()
        }
    }

    /// Stop Lambda container and all services
    struct StopAllCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop-all",
            abstract: "Stop Lambda container and all services"
        )

        func run() async throws {
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.stopWithServices()
        }
    }

    /// Start PostgreSQL database
    struct StartDatabaseCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-database",
            abstract: "Start local PostgreSQL database"
        )

        func run() async throws {
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
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
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.stopDatabase()
        }
    }

    /// Start DynamoDB Local
    struct StartDynamoDBCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-dynamodb",
            abstract: "Start local DynamoDB"
        )

        func run() async throws {
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.startDynamoDB()
        }
    }

    /// Stop DynamoDB Local
    struct StopDynamoDBCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop-dynamodb",
            abstract: "Stop local DynamoDB"
        )

        func run() async throws {
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.stopDynamoDB()
        }
    }

    /// Start MinIO S3
    struct StartS3Command: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-s3",
            abstract: "Start local MinIO S3 service"
        )

        func run() async throws {
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
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
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.stopS3()
        }
    }

    /// Test Lambda container
    struct TestCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test",
            abstract: "Test Lambda container endpoints"
        )

        func run() async throws {
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.testLambda()
        }
    }

    /// Show status of all services
    struct StatusCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show status of Lambda container and services (PostgreSQL + MinIO)"
        )

        func run() async throws {
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            let status = try await service.status()
            printStatus(status, mode: "Linux (Container)")
        }
    }

    /// Setup Docker network (Linux-specific)
    struct SetupNetworkCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "setup-network",
            abstract: "Setup Docker network for Lambda container testing"
        )

        func run() async throws {
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.setupDockerNetwork()
        }
    }

    /// Run Lambda in interactive container (Linux-specific)
    struct RunInteractiveCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run-interactive",
            abstract: "Run Lambda in interactive container shell"
        )

        func run() async throws {
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.runInteractive()
        }
    }

    /// Copy config file
    struct CopyConfigCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "copy-config",
            abstract: "Copy runtime config file to ~/.swiftSampleDemo/"
        )

        func run() async throws {
            let service = LinuxLocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.copyConfig()
        }
    }
}

// MARK: - Status Helper

/// Print status in a formatted way
private func printStatus(_ status: DeploymentStatus, mode: String) {
    let lambdaIcon = status.lambdaState == .running ? "✅" : "⏹️"
    let s3Icon = status.s3State == .running ? "✅" : "⏹️"
    let postgresIcon = status.postgresState == .running ? "✅" : "⏹️"
    let dynamodbIcon = status.dynamodbState == .running ? "✅" : "⏹️"

    print("")
    print("📊 Services Status (\(mode))")
    print("───────────────────────────────")
    print("\(lambdaIcon) Lambda:     \(status.lambdaState)")
    print("\(s3Icon) S3:         \(status.s3State)")
    print("\(postgresIcon) PostgreSQL: \(status.postgresState)")
    print("\(dynamodbIcon) DynamoDB:   \(status.dynamodbState)")
    print("")
}
