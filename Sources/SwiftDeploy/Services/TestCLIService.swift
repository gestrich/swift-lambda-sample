import CLIKit
import Foundation

/// A test service for verifying operation-scoped output streams.
/// Makes several CLI calls to demonstrate output isolation.
public actor TestCLIService {
    private let cliService: CLIService

    public init(cliService: CLIService) {
        self.cliService = cliService
    }

    /// Run a series of test commands that produce output.
    /// Use to verify that operation-scoped output streams capture only this operation's output.
    /// - Parameter output: Optional client-owned stream to receive output (in addition to global stream)
    public func runTestCommands(output: CLIOutputStream? = nil) async throws {
        // Command 1: Echo a message
        _ = try await cliService.execute(
            command: "echo",
            arguments: ["Test command 1: Hello from TestCLIService"],
            output: output
        )

        // Command 2: List current directory (limited output)
        _ = try await cliService.execute(
            command: "ls",
            arguments: ["-la"],
            output: output
        )

        // Command 3: Echo another message
        _ = try await cliService.execute(
            command: "echo",
            arguments: ["Test command 3: Operation complete!"],
            output: output
        )
    }

    /// Run a slow command to test concurrent operation isolation.
    /// - Parameters:
    ///   - seconds: Number of seconds to sleep
    ///   - label: Label to identify this operation in output
    ///   - output: Optional client-owned stream to receive output
    public func runSlowCommand(seconds: Int = 2, label: String, output: CLIOutputStream? = nil) async throws {
        _ = try await cliService.execute(
            command: "echo",
            arguments: ["[\(label)] Starting slow operation..."],
            output: output
        )

        // Use bash to run sleep and echo together
        _ = try await cliService.execute(
            command: "bash",
            arguments: ["-c", "sleep \(seconds) && echo '[\(label)] Slow operation completed after \(seconds) seconds'"],
            output: output
        )
    }

    /// Run multiple echo commands with delays to simulate a multi-step operation.
    /// - Parameters:
    ///   - label: Label to identify this operation
    ///   - steps: Number of steps to run
    ///   - output: Optional client-owned stream to receive output
    public func runMultiStepOperation(label: String, steps: Int = 3, output: CLIOutputStream? = nil) async throws {
        for step in 1...steps {
            _ = try await cliService.execute(
                command: "echo",
                arguments: ["[\(label)] Step \(step) of \(steps)"],
                output: output
            )

            // Small delay between steps
            if step < steps {
                _ = try await cliService.execute(
                    command: "sleep",
                    arguments: ["0.5"],
                    output: output
                )
            }
        }

        _ = try await cliService.execute(
            command: "echo",
            arguments: ["[\(label)] All steps completed!"],
            output: output
        )
    }
}
