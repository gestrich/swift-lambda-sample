import Foundation
import CLISDK
import DeployCoreService
import Uniflow

/// Workflow for stopping the Lambda process.
/// Contains all Lambda stop logic directly, using SDK clients.
public struct XcodeStopLambdaWorkflow: StreamingWorkflow {
    private let cliClient: CLIClient

    // Lambda configuration
    private let lambdaHostPort = 8080
    private let lambdaProcessPattern = "swiftlamb"  // lsof truncates process names

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
    }

    /// Components needed for stopping Lambda.
    public struct Components: Sendable {
        public let workflow: XcodeStopLambdaWorkflow
        public let cliClient: CLIClient
    }

    /// Creates a workflow and associated components by instantiating required clients.
    /// - Returns: Components containing the workflow and clients
    public static func create() -> Components {
        let cliClient = CLIClient()

        let workflow = XcodeStopLambdaWorkflow(cliClient: cliClient)

        return Components(
            workflow: workflow,
            cliClient: cliClient
        )
    }

    /// State updates from the stop Lambda workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checking
            case stopping
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case wasRunning(Bool)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State
    public typealias Options = Void

    /// Stream the stop Lambda workflow.
    /// - Returns: AsyncThrowingStream that yields State updates
    public func stream(options: Void) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        // Check if Lambda is running
        continuation.yield(State(step: .checking))
        let wasRunning = await isLambdaRunning()

        // Stop Lambda
        continuation.yield(State(step: .stopping))

        let pids = await getProcessIDsOnPort(lambdaHostPort)

        if !pids.isEmpty {
            continuation.yield(State(
                step: .stopping,
                detail: .output("Killing process(es): \(pids.joined(separator: ", "))...")
            ))

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

            continuation.yield(State(
                step: .stopping,
                detail: .output("Stopped \(pids.count) process\(pids.count == 1 ? "" : "es")")
            ))
        } else {
            continuation.yield(State(
                step: .stopping,
                detail: .output("No Lambda process found on port \(lambdaHostPort)")
            ))
        }

        continuation.yield(State(step: .complete, detail: .wasRunning(wasRunning)))
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
