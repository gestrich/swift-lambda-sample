import ArgumentParser
import Foundation
import DeployLocalService
import DeployCoreService
import DeployLocalXcodeFeature
import DeployLocalLinuxFeature

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

// MARK: - Xcode Progress Printers

private func printXcodeBuildProgress(_ progress: XcodeBuildWorkflow.State) {
    switch progress.step {
    case .cleaning:
        print("🧹 Cleaning build artifacts...")
    case .building:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🔨 Building Lambda for macOS...")
        }
    case .complete:
        if case .buildPath(let path) = progress.detail {
            print("✅ Build complete: \(path)")
        } else {
            print("✅ Build complete")
        }
    }
}

private func printXcodeStartLambdaProgress(_ progress: XcodeStartLambdaWorkflow.State) {
    switch progress.step {
    case .checkingBuild:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🔍 Checking build...")
        }
    case .building:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🔨 Building Lambda...")
        }
    case .starting:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🚀 Starting Lambda...")
        }
    case .waitingForReady:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("⏳ Waiting for Lambda to be ready...")
        }
    case .complete:
        if case .port(let port) = progress.detail {
            print("✅ Lambda running on port \(port)")
        } else {
            print("✅ Lambda started")
        }
    }
}

private func printXcodeStopLambdaProgress(_ progress: XcodeStopLambdaWorkflow.State) {
    switch progress.step {
    case .checking:
        print("🔍 Checking Lambda status...")
    case .stopping:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🛑 Stopping Lambda...")
        }
    case .complete:
        if case .wasRunning(let wasRunning) = progress.detail {
            if wasRunning {
                print("✅ Lambda stopped")
            } else {
                print("ℹ️  Lambda was not running")
            }
        } else {
            print("✅ Lambda stopped")
        }
    }
}

private func printXcodeStartServicesProgress(_ progress: XcodeStartServicesWorkflow.State) {
    switch progress.step {
    case .startingDatabase:
        if case .serviceStarted(_) = progress.detail {
            print("✅ PostgreSQL started")
        } else {
            print("🐘 Starting PostgreSQL...")
        }
    case .startingS3:
        if case .serviceStarted(_) = progress.detail {
            print("✅ MinIO S3 started")
        } else {
            print("📦 Starting MinIO S3...")
        }
    case .creatingBucket:
        print("🪣 Creating S3 bucket...")
    case .startingDynamoDB:
        if case .serviceStarted(_) = progress.detail {
            print("✅ DynamoDB started")
        } else {
            print("⚡ Starting DynamoDB...")
        }
    case .complete:
        print("✅ All services started")
    }
}

private func printXcodeStopServicesProgress(_ progress: XcodeStopServicesWorkflow.State) {
    switch progress.step {
    case .stoppingDatabase:
        if case .serviceStopped(_) = progress.detail {
            print("✅ PostgreSQL stopped")
        } else {
            print("🐘 Stopping PostgreSQL...")
        }
    case .stoppingS3:
        if case .serviceStopped(_) = progress.detail {
            print("✅ MinIO S3 stopped")
        } else {
            print("📦 Stopping MinIO S3...")
        }
    case .stoppingDynamoDB:
        if case .serviceStopped(_) = progress.detail {
            print("✅ DynamoDB stopped")
        } else {
            print("⚡ Stopping DynamoDB...")
        }
    case .complete:
        print("✅ All services stopped")
    }
}

private func printXcodeStartAllProgress(_ progress: XcodeStartAllWorkflow.State) {
    switch progress.step {
    case .startingServices:
        if case .servicesState(let servicesProgress) = progress.detail {
            printXcodeStartServicesProgress(servicesProgress)
        } else {
            print("🔄 Starting services...")
        }
    case .startingLambda:
        if case .lambdaState(let lambdaProgress) = progress.detail {
            printXcodeStartLambdaProgress(lambdaProgress)
        } else {
            print("🔄 Starting Lambda...")
        }
    case .complete:
        if case .port(let port) = progress.detail {
            print("")
            print("✅ All services and Lambda running on port \(port)")
        } else {
            print("✅ All services started")
        }
    }
}

private func printXcodeStopAllProgress(_ progress: XcodeStopAllWorkflow.State) {
    switch progress.step {
    case .stoppingLambda:
        if case .lambdaState(let lambdaProgress) = progress.detail {
            printXcodeStopLambdaProgress(lambdaProgress)
        } else {
            print("🔄 Stopping Lambda...")
        }
    case .stoppingServices:
        if case .servicesState(let servicesProgress) = progress.detail {
            printXcodeStopServicesProgress(servicesProgress)
        } else {
            print("🔄 Stopping services...")
        }
    case .complete:
        print("")
        print("✅ All Lambda and services stopped")
    }
}

private func printXcodeTestProgress(_ progress: XcodeTestWorkflow.State) {
    switch progress.step {
    case .checkingLambda:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🔍 Checking Lambda status...")
        }
    case .testingFileUpload:
        if case .testPassed(let name) = progress.detail {
            print("✅ \(name)")
        } else {
            print("📤 Testing file upload...")
        }
    case .testingFileList:
        if case .testPassed(let name) = progress.detail {
            print("✅ \(name)")
        } else {
            print("📋 Testing file list...")
        }
    case .testingFileDownload:
        if case .testPassed(let name) = progress.detail {
            print("✅ \(name)")
        } else {
            print("📥 Testing file download...")
        }
    case .testingDatabaseInit:
        if case .testPassed(let name) = progress.detail {
            print("✅ \(name)")
        } else {
            print("🗄️  Testing database init...")
        }
    case .complete:
        print("")
        print("✅ All tests passed")
    }
}

private func printXcodeCopyConfigProgress(_ progress: XcodeCopyConfigWorkflow.State) {
    switch progress.step {
    case .copying:
        if case .copiedFile(let file) = progress.detail {
            print("📄 Copied \(file)")
        } else {
            print("📋 Copying config files...")
        }
    case .complete:
        if case .destinationPath(let path) = progress.detail {
            print("✅ Config copied to \(path)")
        } else {
            print("✅ Config copied")
        }
    }
}

// MARK: - Linux Progress Printers

private func printLinuxBuildProgress(_ progress: LinuxBuildWorkflow.State) {
    switch progress.step {
    case .cleaning:
        print("🧹 Cleaning build artifacts...")
    case .building:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🐳 Building Lambda for Linux (Docker)...")
        }
    case .complete:
        if case .buildPath(let path) = progress.detail {
            print("✅ Build complete: \(path)")
        } else {
            print("✅ Build complete")
        }
    }
}

private func printLinuxStartLambdaProgress(_ progress: LinuxStartLambdaWorkflow.State) {
    switch progress.step {
    case .checkingBuild:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🔍 Checking build...")
        }
    case .starting:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🐳 Starting Lambda container...")
        }
    case .waitingForReady:
        print("⏳ Waiting for Lambda to be ready...")
    case .complete:
        if case .port(let port) = progress.detail {
            print("✅ Lambda container running on port \(port)")
        } else {
            print("✅ Lambda container started")
        }
    }
}

private func printLinuxStopLambdaProgress(_ progress: LinuxStopLambdaWorkflow.State) {
    switch progress.step {
    case .checking:
        print("🔍 Checking Lambda container status...")
    case .stopping:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🛑 Stopping Lambda container...")
        }
    case .complete:
        if case .wasRunning(let wasRunning) = progress.detail {
            if wasRunning {
                print("✅ Lambda container stopped")
            } else {
                print("ℹ️  Lambda container was not running")
            }
        } else {
            print("✅ Lambda container stopped")
        }
    }
}

private func printLinuxStartServicesProgress(_ progress: LinuxStartServicesWorkflow.State) {
    switch progress.step {
    case .startingDatabase:
        if case .serviceStarted(_) = progress.detail {
            print("✅ PostgreSQL started")
        } else {
            print("🐘 Starting PostgreSQL...")
        }
    case .startingS3:
        if case .serviceStarted(_) = progress.detail {
            print("✅ MinIO S3 started")
        } else {
            print("📦 Starting MinIO S3...")
        }
    case .creatingBucket:
        print("🪣 Creating S3 bucket...")
    case .startingDynamoDB:
        if case .serviceStarted(_) = progress.detail {
            print("✅ DynamoDB started")
        } else {
            print("⚡ Starting DynamoDB...")
        }
    case .complete:
        print("✅ All services started")
    }
}

private func printLinuxStopServicesProgress(_ progress: LinuxStopServicesWorkflow.State) {
    switch progress.step {
    case .stoppingDatabase:
        if case .serviceStopped(_) = progress.detail {
            print("✅ PostgreSQL stopped")
        } else {
            print("🐘 Stopping PostgreSQL...")
        }
    case .stoppingS3:
        if case .serviceStopped(_) = progress.detail {
            print("✅ MinIO S3 stopped")
        } else {
            print("📦 Stopping MinIO S3...")
        }
    case .stoppingDynamoDB:
        if case .serviceStopped(_) = progress.detail {
            print("✅ DynamoDB stopped")
        } else {
            print("⚡ Stopping DynamoDB...")
        }
    case .complete:
        print("✅ All services stopped")
    }
}

private func printLinuxStartAllProgress(_ progress: LinuxStartAllWorkflow.State) {
    switch progress.step {
    case .startingServices:
        if case .servicesState(let servicesProgress) = progress.detail {
            printLinuxStartServicesProgress(servicesProgress)
        } else {
            print("🔄 Starting services...")
        }
    case .setupNetwork:
        if case .networkState(let networkProgress) = progress.detail {
            printLinuxSetupNetworkProgress(networkProgress)
        } else {
            print("🌐 Setting up Docker network...")
        }
    case .startingLambda:
        if case .lambdaState(let lambdaProgress) = progress.detail {
            printLinuxStartLambdaProgress(lambdaProgress)
        } else {
            print("🔄 Starting Lambda container...")
        }
    case .complete:
        if case .port(let port) = progress.detail {
            print("")
            print("✅ All services and Lambda container running on port \(port)")
        } else {
            print("✅ All services started")
        }
    }
}

private func printLinuxStopAllProgress(_ progress: LinuxStopAllWorkflow.State) {
    switch progress.step {
    case .stoppingLambda:
        if case .lambdaState(let lambdaProgress) = progress.detail {
            printLinuxStopLambdaProgress(lambdaProgress)
        } else {
            print("🔄 Stopping Lambda container...")
        }
    case .stoppingServices:
        if case .servicesState(let servicesProgress) = progress.detail {
            printLinuxStopServicesProgress(servicesProgress)
        } else {
            print("🔄 Stopping services...")
        }
    case .complete:
        print("")
        print("✅ All Lambda container and services stopped")
    }
}

private func printLinuxTestProgress(_ progress: LinuxTestWorkflow.State) {
    switch progress.step {
    case .checkingLambda:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🔍 Checking Lambda container status...")
        }
    case .testingFileUpload:
        if case .testPassed(let name) = progress.detail {
            print("✅ \(name)")
        } else {
            print("📤 Testing file upload...")
        }
    case .testingFileList:
        if case .testPassed(let name) = progress.detail {
            print("✅ \(name)")
        } else {
            print("📋 Testing file list...")
        }
    case .testingFileDownload:
        if case .testPassed(let name) = progress.detail {
            print("✅ \(name)")
        } else {
            print("📥 Testing file download...")
        }
    case .testingDatabaseInit:
        if case .testPassed(let name) = progress.detail {
            print("✅ \(name)")
        } else {
            print("🗄️  Testing database init...")
        }
    case .complete:
        print("")
        print("✅ All tests passed")
    }
}

private func printLinuxCopyConfigProgress(_ progress: LinuxCopyConfigWorkflow.State) {
    switch progress.step {
    case .copying:
        if case .copiedFile(let file) = progress.detail {
            print("📄 Copied \(file)")
        } else {
            print("📋 Copying config files...")
        }
    case .complete:
        if case .destinationPath(let path) = progress.detail {
            print("✅ Config copied to \(path)")
        } else {
            print("✅ Config copied")
        }
    }
}

private func printLinuxSetupNetworkProgress(_ progress: LinuxSetupNetworkWorkflow.State) {
    switch progress.step {
    case .creatingNetwork:
        switch progress.detail {
        case .networkCreated(let name):
            print("✅ Network '\(name)' created")
        case .output(let message):
            print("  ✓ \(message)")
        default:
            print("🌐 Creating Docker network...")
        }
    case .connectingContainers:
        switch progress.detail {
        case .containerConnected(let name):
            print("  🔗 Connected \(name)")
        case .containerSkipped(let name, let reason):
            print("  ⚠️  Skipped \(name) (\(reason))")
        case .output(let message):
            print("  ✓ \(message)")
        default:
            print("🔗 Connecting containers to network...")
        }
    case .complete:
        print("✅ Docker network setup complete")
    }
}

private func printLinuxRunInteractiveProgress(_ progress: LinuxRunInteractiveWorkflow.State) {
    switch progress.step {
    case .preparing:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🔧 Preparing interactive container...")
        }
    case .launching:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🐳 Launching interactive container...")
        }
    case .complete:
        print("✅ Interactive session ended")
    }
}

// MARK: - Status Progress Printers

private func printXcodeStatusProgress(_ progress: XcodeStatusWorkflow.State) {
    switch progress.step {
    case .checkingLambda:
        print("🔍 Checking Lambda status...")
    case .checkingS3:
        print("🔍 Checking S3 status...")
    case .checkingDatabase:
        print("🔍 Checking PostgreSQL status...")
    case .checkingDynamoDB:
        print("🔍 Checking DynamoDB status...")
    case .complete:
        if case .status(let status) = progress.detail {
            printStatus(status, mode: "Mac (Native)")
        }
    }
}

private func printLinuxStatusProgress(_ progress: LinuxStatusWorkflow.State) {
    switch progress.step {
    case .checkingLambda:
        print("🔍 Checking Lambda container status...")
    case .checkingS3:
        print("🔍 Checking S3 status...")
    case .checkingDatabase:
        print("🔍 Checking PostgreSQL status...")
    case .checkingDynamoDB:
        print("🔍 Checking DynamoDB status...")
    case .complete:
        if case .status(let status) = progress.detail {
            printStatus(status, mode: "Linux (Container)")
        }
    }
}
