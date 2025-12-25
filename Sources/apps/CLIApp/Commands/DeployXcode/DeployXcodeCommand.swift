import ArgumentParser
import DeployCoreService
import DeployLocalService
import DeployXcodeFeature
import Foundation
import LocalServicesFeature

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
            let components = XcodeBuildUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = XcodeBuildUseCase.Options(clean: clean)

            for try await progress in components.useCase.stream(options: options) {
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
            let components = XcodeStartLambdaUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.useCase.stream() {
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
            let components = XcodeStopLambdaUseCase.create()

            for try await progress in components.useCase.stream() {
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
            let components = XcodeStartAllUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.useCase.stream() {
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
            let components = XcodeStopAllUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.useCase.stream() {
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
            let components = StartServicesUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath,
                configuration: .xcode
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
                configuration: .xcode
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
                configuration: .xcode
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
                configuration: .xcode
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
                configuration: .xcode
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
                configuration: .xcode
            )
            let options = StopServicesUseCase.Options.only(.s3)

            for try await progress in components.useCase.stream(options: options) {
                printLocalServicesStopProgress(progress)
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
            let components = XcodeTestUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            for try await progress in components.useCase.stream() {
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
            let components = XcodeStatusUseCase.create()

            for try await progress in components.useCase.stream() {
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
            let components = XcodeCopyConfigUseCase.create(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let options = XcodeCopyConfigUseCase.Options()

            for try await progress in components.useCase.stream(options: options) {
                printXcodeCopyConfigProgress(progress)
            }
        }
    }
}
