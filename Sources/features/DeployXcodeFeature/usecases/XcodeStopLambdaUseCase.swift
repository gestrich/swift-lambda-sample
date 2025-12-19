import Foundation
import CLISDK
import DeployCoreService
import Uniflow

/// Use case for stopping the Lambda process.
/// Contains all Lambda stop logic directly, using SDK clients.
public struct XcodeStopLambdaUseCase: StreamingUseCase {
    private let cliClient: CLIClient

    // Lambda configuration
    private let lambdaHostPort = 8080
    private let lambdaProcessPattern = "swiftlamb"  // lsof truncates process names

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
    }

    /// Components needed for stopping Lambda.
    public struct Components: Sendable {
        public let useCase: XcodeStopLambdaUseCase
        public let cliClient: CLIClient
    }

    /// Creates a use case and associated components by instantiating required clients.
    /// - Returns: Components containing the use case and clients
    public static func create() -> Components {
        let cliClient = CLIClient()

        let useCase = XcodeStopLambdaUseCase(cliClient: cliClient)

        return Components(
            useCase: useCase,
            cliClient: cliClient
        )
    }

    public typealias State = XcodeUseCaseState
    public typealias Result = XcodeUseCaseState
    public typealias Options = Void

    /// Stream the stop Lambda use case.
    /// - Returns: AsyncThrowingStream that yields XcodeUseCaseState updates
    public func stream(options: Void) -> AsyncThrowingStream<XcodeUseCaseState, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runUseCase(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runUseCase(
        continuation: AsyncThrowingStream<XcodeUseCaseState, Error>.Continuation
    ) async throws {
        let startTime = Date()

        // Stop Lambda
        continuation.yield(.stoppingLambda(XcodeUseCaseState.LambdaProgress(
            step: .stopping,
            startTime: startTime
        )))

        let pids = await getProcessIDsOnPort(lambdaHostPort)

        if !pids.isEmpty {
            for pid in pids {
                let killResult = try await cliClient.executeForResult(
                    Kill(pid: pid),
                    printCommand: false
                )

                if !killResult.isSuccess {
                    throw DeployError.commandFailed(
                        command: Kill(pid: pid).commandString,
                        exitCode: killResult.exitCode,
                        output: killResult.output
                    )
                }
            }
        }

        // Completed - yield snapshot with Lambda stopped
        let snapshot = XcodeSnapshot(
            serviceStatus: DeploymentStatus(
                lambdaState: .stopped,
                s3State: .stopped,
                postgresState: .stopped,
                dynamodbState: .stopped
            ),
            buildStatus: .notBuilt
        )
        continuation.yield(.completed(snapshot))
        continuation.finish()
    }

    // MARK: - Status Check Helpers

    /// Check if Lambda is running (native process on port, not Docker)
    public func isLambdaRunning() async -> Bool {
        let output = await getPortInfo(lambdaHostPort)
        guard !output.isEmpty else { return false }

        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.contains(lambdaProcessPattern) && !lowercased.contains("docker") {
                return true
            }
        }
        return false
    }

    // MARK: - Private Helpers

    /// Get information about what's using a port
    private func getPortInfo(_ port: Int) async -> String {
        do {
            let result = try await cliClient.executeForResult(
                Lsof(port: ":\(port)"),
                printCommand: false
            )
            guard result.isSuccess else { return "" }
            return result.stdout
        } catch {
            return ""
        }
    }

    /// Get PIDs of processes using a specific port
    private func getProcessIDsOnPort(_ port: Int) async -> [String] {
        do {
            let result = try await cliClient.executeForResult(
                Lsof(port: ":\(port)", pidOnly: true),
                printCommand: false
            )
            guard result.isSuccess && !result.stdout.isEmpty else {
                return []
            }
            let currentPID = String(ProcessInfo.processInfo.processIdentifier)
            return result.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty && $0 != currentPID }
        } catch {
            return []
        }
    }
}
