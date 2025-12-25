import BrewCLISDK
import CLISDK
import Foundation
import Uniflow

/// Use case that installs a specific dependency
public struct DependencyInstallUseCase: StreamingUseCase {
    private let cliClient: CLIClient
    private let brewClient: BrewClient

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
        self.brewClient = BrewClient(cliClient: cliClient)
    }

    public struct State: Sendable {
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

    public typealias Result = State

    /// Options for the use case
    public struct Options: Sendable {
        public let tool: CLITool

        public init(tool: CLITool) {
            self.tool = tool
        }
    }

    /// Stream the install use case for a specific CLI tool
    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(State(step: .preparing))

                    continuation.yield(State(step: .installing))
                    try await install(options.tool)

                    continuation.yield(State(step: .verifying))
                    let status = await verify(options.tool)

                    continuation.yield(State(step: .complete, detail: .installed(status)))
                    continuation.finish()
                } catch {
                    continuation.yield(State(step: .complete, detail: .failed(error.localizedDescription)))
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
        let statusUseCase = DependencyStatusUseCase(cliClient: cliClient)
        return await statusUseCase.checkTool(tool)
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
