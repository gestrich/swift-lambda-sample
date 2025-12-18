import ArgumentParser
import Foundation
import DeployLocalService
import DeployCoreService
import DeployXcodeFeature

// MARK: - Deploy Xcode Command (Native macOS)

/// Native macOS development workflow (fast iteration)
struct DeployXcodeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deploy-xcode",
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

// MARK: - Deploy Xcode Subcommands

extension DeployXcodeCommand {
    /// Build Lambda for macOS (native)
    struct BuildCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "build",
            abstract: "Build Lambda for macOS (native Swift build)"
        )

        @Flag(name: .long, help: "Clean build artifacts before building")
        var clean: Bool = false

        func run() async throws {
            let components = XcodeBuildWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = XcodeBuildWorkflow.Options(clean: clean)

            for try await progress in components.workflow.stream(options: options) {
                printXcodeBuildProgress(progress)
            }
        }
    }

    /// Start Lambda locally (native process)
    struct StartCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start",
            abstract: "Start Lambda locally (native process)"
        )

        func run() async throws {
            let components = XcodeStartLambdaWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.workflow.stream() {
                printXcodeStartLambdaProgress(progress)
            }
        }
    }

    /// Stop Lambda (native process)
    struct StopCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop",
            abstract: "Stop Lambda (native process)"
        )

        func run() async throws {
            let components = XcodeStopLambdaWorkflow.create()

            for try await progress in components.workflow.stream() {
                printXcodeStopLambdaProgress(progress)
            }
        }
    }

    /// Start Lambda with all services (native process)
    struct StartAllCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start-all",
            abstract: "Start Lambda with services (PostgreSQL + MinIO + native Lambda)"
        )

        func run() async throws {
            let components = XcodeStartAllWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.workflow.stream() {
                printXcodeStartAllProgress(progress)
            }
        }
    }

    /// Stop Lambda and all services
    struct StopAllCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop-all",
            abstract: "Stop Lambda and all services"
        )

        func run() async throws {
            let components = XcodeStopAllWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.workflow.stream() {
                printXcodeStopAllProgress(progress)
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
            let components = XcodeStartServicesWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = XcodeStartServicesWorkflow.Options.only(.database)

            for try await progress in components.workflow.stream(options: options) {
                printXcodeStartServicesProgress(progress)
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
            let components = XcodeStopServicesWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = XcodeStopServicesWorkflow.Options.only(.database)

            for try await progress in components.workflow.stream(options: options) {
                printXcodeStopServicesProgress(progress)
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
            let components = XcodeStartServicesWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = XcodeStartServicesWorkflow.Options.only(.dynamodb)

            for try await progress in components.workflow.stream(options: options) {
                printXcodeStartServicesProgress(progress)
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
            let components = XcodeStopServicesWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = XcodeStopServicesWorkflow.Options.only(.dynamodb)

            for try await progress in components.workflow.stream(options: options) {
                printXcodeStopServicesProgress(progress)
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
            let components = XcodeStartServicesWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = XcodeStartServicesWorkflow.Options.only(.s3)

            for try await progress in components.workflow.stream(options: options) {
                printXcodeStartServicesProgress(progress)
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
            let components = XcodeStopServicesWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = XcodeStopServicesWorkflow.Options.only(.s3)

            for try await progress in components.workflow.stream(options: options) {
                printXcodeStopServicesProgress(progress)
            }
        }
    }

    /// Test local Lambda
    struct TestCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test",
            abstract: "Test local Lambda endpoints"
        )

        func run() async throws {
            let components = XcodeTestWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.workflow.stream() {
                printXcodeTestProgress(progress)
            }
        }
    }

    /// Show status of all services
    struct StatusCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show status of Lambda and services (PostgreSQL + MinIO)"
        )

        func run() async throws {
            let components = XcodeStatusWorkflow.create()

            for try await progress in components.workflow.stream() {
                printXcodeStatusProgress(progress)
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
            let components = XcodeCopyConfigWorkflow.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = XcodeCopyConfigWorkflow.Options()

            for try await progress in components.workflow.stream(options: options) {
                printXcodeCopyConfigProgress(progress)
            }
        }
    }
}
