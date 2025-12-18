import ArgumentParser
import Foundation
import DeployLocalService
import DeployCoreService
import DeployLinuxFeature

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
            let components = LinuxBuildWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = LinuxBuildWorkflow.Options(clean: clean)

            for try await progress in components.workflow.stream(options: options) {
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
            let components = LinuxStartLambdaWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.workflow.stream() {
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
            let components = LinuxStopLambdaWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.workflow.stream() {
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
            let components = LinuxStartAllWorkflow.create(workingDirectory: workingDirectory)

            for try await progress in components.workflow.stream() {
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
            let components = LinuxStopAllWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.workflow.stream() {
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
            let components = LinuxStartServicesWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = LinuxStartServicesWorkflow.Options.only(.database)

            for try await progress in components.workflow.stream(options: options) {
                printLinuxStartServicesProgress(progress)
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
            let components = LinuxStopServicesWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = LinuxStopServicesWorkflow.Options.only(.database)

            for try await progress in components.workflow.stream(options: options) {
                printLinuxStopServicesProgress(progress)
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
            let components = LinuxStartServicesWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = LinuxStartServicesWorkflow.Options.only(.dynamodb)

            for try await progress in components.workflow.stream(options: options) {
                printLinuxStartServicesProgress(progress)
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
            let components = LinuxStopServicesWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = LinuxStopServicesWorkflow.Options.only(.dynamodb)

            for try await progress in components.workflow.stream(options: options) {
                printLinuxStopServicesProgress(progress)
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
            let components = LinuxStartServicesWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = LinuxStartServicesWorkflow.Options.only(.s3)

            for try await progress in components.workflow.stream(options: options) {
                printLinuxStartServicesProgress(progress)
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
            let components = LinuxStopServicesWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = LinuxStopServicesWorkflow.Options.only(.s3)

            for try await progress in components.workflow.stream(options: options) {
                printLinuxStopServicesProgress(progress)
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
            let components = LinuxTestWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.workflow.stream() {
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
            let components = LinuxStatusWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.workflow.stream() {
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
            let components = LinuxSetupNetworkWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.workflow.stream() {
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
            let components = LinuxRunInteractiveWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.workflow.stream() {
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
            let components = LinuxCopyConfigWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = LinuxCopyConfigWorkflow.Options()

            for try await progress in components.workflow.stream(options: options) {
                printLinuxCopyConfigProgress(progress)
            }
        }
    }
}
