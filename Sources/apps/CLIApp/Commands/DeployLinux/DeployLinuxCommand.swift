import ArgumentParser
import Foundation
import DeployLocalService
import DeployCoreService
import DeployLinuxFeature
import LocalServicesFeature

// MARK: - Deploy Linux Command (Container)

/// Linux container deployment workflow (AWS Lambda compatible)
struct DeployLinuxCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deploy-linux",
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

// MARK: - Deploy Linux Subcommands

extension DeployLinuxCommand {
    /// Build Lambda for Linux (Docker-based)
    struct BuildCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "build",
            abstract: "Build Lambda for Linux (AMD64, Docker-based)"
        )

        @Flag(name: .long, help: "Clean build artifacts before building")
        var clean: Bool = false

        func run() async throws {
            let components = LinuxBuildUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = LinuxBuildUseCase.Options(clean: clean)

            for try await progress in components.useCase.stream(options: options) {
                printLinuxBuildProgress(progress)
            }
        }
    }

    /// Start Lambda container
    struct StartCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start",
            abstract: "Start Lambda container"
        )

        func run() async throws {
            let components = LinuxStartLambdaUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.useCase.stream() {
                printLinuxStartLambdaProgress(progress)
            }
        }
    }

    /// Stop Lambda container
    struct StopCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop",
            abstract: "Stop Lambda container"
        )

        func run() async throws {
            let components = LinuxStopLambdaUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.useCase.stream() {
                printLinuxStopLambdaProgress(progress)
            }
        }
    }

    /// Start Lambda container with all services
    struct StartAllCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-all",
            abstract: "Start Lambda with services (PostgreSQL + MinIO + container)"
        )

        func run() async throws {
            let workingDirectory = FileManager.default.currentDirectoryPath
            let components = LinuxStartAllUseCase.create(workingDirectory: workingDirectory)

            for try await progress in components.useCase.stream() {
                printLinuxStartAllProgress(progress)
            }
        }
    }

    /// Stop Lambda container and all services
    struct StopAllCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop-all",
            abstract: "Stop Lambda container and all services"
        )

        func run() async throws {
            let components = LinuxStopAllUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.useCase.stream() {
                printLinuxStopAllProgress(progress)
            }
        }
    }

    /// Start PostgreSQL database
    struct StartDatabaseCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-database",
            abstract: "Start local PostgreSQL database"
        )

        func run() async throws {
            let components = StartServicesUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath,
                configuration: .linux
            )
            let options = StartServicesUseCase.Options.only(.database)

            for try await progress in components.useCase.stream(options: options) {
                printLocalServicesStartProgress(progress)
            }
        }
    }

    /// Stop PostgreSQL database
    struct StopDatabaseCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop-database",
            abstract: "Stop local PostgreSQL database"
        )

        func run() async throws {
            let components = StopServicesUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath,
                configuration: .linux
            )
            let options = StopServicesUseCase.Options.only(.database)

            for try await progress in components.useCase.stream(options: options) {
                printLocalServicesStopProgress(progress)
            }
        }
    }

    /// Start DynamoDB Local
    struct StartDynamoDBCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-dynamodb",
            abstract: "Start local DynamoDB"
        )

        func run() async throws {
            let components = StartServicesUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath,
                configuration: .linux
            )
            let options = StartServicesUseCase.Options.only(.dynamodb)

            for try await progress in components.useCase.stream(options: options) {
                printLocalServicesStartProgress(progress)
            }
        }
    }

    /// Stop DynamoDB Local
    struct StopDynamoDBCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop-dynamodb",
            abstract: "Stop local DynamoDB"
        )

        func run() async throws {
            let components = StopServicesUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath,
                configuration: .linux
            )
            let options = StopServicesUseCase.Options.only(.dynamodb)

            for try await progress in components.useCase.stream(options: options) {
                printLocalServicesStopProgress(progress)
            }
        }
    }

    /// Start MinIO S3
    struct StartS3Command: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-s3",
            abstract: "Start local MinIO S3 service"
        )

        func run() async throws {
            let components = StartServicesUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath,
                configuration: .linux
            )
            let options = StartServicesUseCase.Options.only(.s3)

            for try await progress in components.useCase.stream(options: options) {
                printLocalServicesStartProgress(progress)
            }
        }
    }

    /// Stop MinIO S3
    struct StopS3Command: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop-s3",
            abstract: "Stop local MinIO S3 service"
        )

        func run() async throws {
            let components = StopServicesUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath,
                configuration: .linux
            )
            let options = StopServicesUseCase.Options.only(.s3)

            for try await progress in components.useCase.stream(options: options) {
                printLocalServicesStopProgress(progress)
            }
        }
    }

    /// Test Lambda container
    struct TestCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test",
            abstract: "Test Lambda container endpoints"
        )

        func run() async throws {
            let components = LinuxTestUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.useCase.stream() {
                printLinuxTestProgress(progress)
            }
        }
    }

    /// Show status of all services
    struct StatusCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show status of Lambda container and services (PostgreSQL + MinIO)"
        )

        func run() async throws {
            let components = LinuxStatusUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.useCase.stream() {
                printLinuxStatusProgress(progress)
            }
        }
    }

    /// Setup Docker network (Linux-specific)
    struct SetupNetworkCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "setup-network",
            abstract: "Setup Docker network for Lambda container testing"
        )

        func run() async throws {
            let components = LinuxSetupNetworkUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.useCase.stream() {
                printLinuxSetupNetworkProgress(progress)
            }
        }
    }

    /// Run Lambda in interactive container (Linux-specific)
    struct RunInteractiveCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run-interactive",
            abstract: "Run Lambda in interactive container shell"
        )

        func run() async throws {
            let components = LinuxRunInteractiveUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.useCase.stream() {
                printLinuxRunInteractiveProgress(progress)
            }
        }
    }

    /// Copy config file
    struct CopyConfigCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "copy-config",
            abstract: "Copy runtime config file to ~/.swiftSampleDemo/"
        )

        func run() async throws {
            let components = LinuxCopyConfigUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = LinuxCopyConfigUseCase.Options()

            for try await progress in components.useCase.stream(options: options) {
                printLinuxCopyConfigProgress(progress)
            }
        }
    }
}
