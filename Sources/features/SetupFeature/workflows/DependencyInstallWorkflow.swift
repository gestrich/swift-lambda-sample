import Foundation
import CLISDK
import BrewCLISDK

/// Workflow that installs a specific dependency
public struct DependencyInstallWorkflow: Sendable {
    private let cliClient: CLIClient
    private let brewClient: BrewClient

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
        self.brewClient = BrewClient(cliClient: cliClient)
    }

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case preparing
            case installing
            case verifying
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case installed(CLIToolStatus)
            case failed(String)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    /// Install a specific CLI tool
    public func run(tool: CLITool) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(Progress(step: .preparing))

                    continuation.yield(Progress(step: .installing))
                    try await install(tool)

                    continuation.yield(Progress(step: .verifying))
                    let status = await verify(tool)

                    continuation.yield(Progress(step: .complete, detail: .installed(status)))
                    continuation.finish()
                } catch {
                    continuation.yield(Progress(step: .complete, detail: .failed(error.localizedDescription)))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func install(_ tool: CLITool) async throws {
        switch tool {
        case .homebrew:
            throw DependencyInstallError.manualInstallRequired(tool)

        case .nodejs:
            try await brewClient.install("node")

        case .docker:
            try await brewClient.install("docker", cask: true)

        case .awsCLI:
            try await brewClient.install("awscli")

        case .cdk:
            throw DependencyInstallError.manualInstallRequired(tool)

        case .githubCLI:
            try await brewClient.install("gh")
        }
    }

    private func verify(_ tool: CLITool) async -> CLIToolStatus {
        let statusWorkflow = DependencyStatusWorkflow(cliClient: cliClient)
        return await statusWorkflow.checkTool(tool)
    }
}

/// Errors that can occur during dependency installation
public enum DependencyInstallError: Error, LocalizedError {
    case manualInstallRequired(CLITool)

    public var errorDescription: String? {
        switch self {
        case .manualInstallRequired(let tool):
            return "\(tool.displayName) requires manual installation"
        }
    }
}
