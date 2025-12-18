import Foundation
import CLISDK
import DeployLocalService
import StorageService
import Uniflow

/// Workflow for copying configuration files to `~/.swiftSampleDemo/`.
/// Contains all copy config logic directly, using LocalStorageService.
public struct LinuxCopyConfigWorkflow: StreamingWorkflow {
    private let storageService: LocalStorageService
    private let workingDirectory: String

    public init(
        storageService: LocalStorageService,
        workingDirectory: String
    ) {
        self.storageService = storageService
        self.workingDirectory = workingDirectory
    }

    /// Components needed for copy config operations.
    public struct Components: Sendable {
        public let workflow: LinuxCopyConfigWorkflow
    }

    /// Creates a workflow and associated components by instantiating required services.
    /// - Parameter workingDirectory: The working directory for the workflow
    /// - Returns: Components containing the workflow
    public static func create(workingDirectory: String) -> Components {
        let storageService = LocalStorageService()

        let workflow = LinuxCopyConfigWorkflow(
            storageService: storageService,
            workingDirectory: workingDirectory
        )

        return Components(workflow: workflow)
    }

    /// State updates from the copy config workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case copying
            case complete
        }

        public enum Detail: Sendable {
            case copiedFile(String)
            case destinationPath(String)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State

    /// Options for the copy config workflow.
    public struct Options: Sendable {
        public let sourcePath: String?

        public init(sourcePath: String? = nil) {
            self.sourcePath = sourcePath
        }
    }

    /// Stream the copy config workflow.
    /// - Parameter options: Copy config options
    /// - Returns: AsyncThrowingStream that yields State updates
    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(sourcePath: options.sourcePath, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        sourcePath: String?,
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        continuation.yield(State(step: .copying))

        // Ensure base directory exists
        try storageService.ensureDirectoryExists(at: storageService.baseDataDirectory)

        // Determine source and destination paths
        let appConfigSource: String
        if let customPath = sourcePath {
            appConfigSource = customPath
        } else {
            appConfigSource = "\(workingDirectory)/\(AppConfigFileKey.filename)"
        }
        let appConfigDest = storageService.filePath(for: AppConfigFileKey.self)

        // Verify source file exists
        let fm = FileManager.default
        guard fm.fileExists(atPath: appConfigSource) else {
            throw CLIClientError.invalidWorkingDirectory("App config file not found at: \(appConfigSource)")
        }

        // Remove existing destination file if present
        if fm.fileExists(atPath: appConfigDest) {
            try fm.removeItem(atPath: appConfigDest)
        }

        // Copy file
        try fm.copyItem(atPath: appConfigSource, toPath: appConfigDest)

        continuation.yield(State(step: .copying, detail: .copiedFile(AppConfigFileKey.filename)))
        continuation.yield(State(step: .complete, detail: .destinationPath(storageService.baseDataDirectory + "/")))
        continuation.finish()
    }
}
