import ArgumentParser
import CLIKit
import Foundation

/// Development and testing commands
struct DevCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dev",
        abstract: "Development and testing commands",
        subcommands: [
            TestGlobalStreamCommand.self
        ]
    )
}

extension DevCommand {
    /// Test the global CLI output stream
    struct TestGlobalStreamCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test-global-stream",
            abstract: "Test the global CLI output stream with multiple subscribers"
        )

        func run() async throws {
            let subscribers = 2

            print("🧪 Testing BroadcastAsyncSequence with global CLI output stream")
            print("   Subscribers: \(subscribers)")
            print()

            // Start subscriber tasks
            var subscriberTasks: [Task<Void, Never>] = []

            for i in 1...subscribers {
                let subscriberId = i
                let task = Task { @MainActor in
                    print("📡 Subscriber \(subscriberId) started listening")
                    var messageCount = 0
                    for await output in CLIService.globalOutput {
                        messageCount += 1
                        switch output {
                        case .stdout(let text):
                            print("   [Sub \(subscriberId)] stdout: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
                        case .stderr(let text):
                            print("   [Sub \(subscriberId)] stderr: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
                        case .exit(let code):
                            print("   [Sub \(subscriberId)] exit: \(code)")
                            return
                        case .error(let error):
                            print("   [Sub \(subscriberId)] error: \(error)")
                            return
                        }
                    }
                    print("📡 Subscriber \(subscriberId) finished (received \(messageCount) messages)")
                }
                subscriberTasks.append(task)
            }

            // Give subscribers time to register
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Run a simple command - this will broadcast to all subscribers via globalOutput
            print("\n🚀 Running command: echo 'Hello from global stream test!'")
            let result = try await CLIService.shared.execute(
                command: "echo",
                arguments: ["Hello from global stream test!"],
                printCommand: true
            )

            print("\n📊 Command result:")
            print("   Exit code: \(result.exitCode)")
            print("   Duration: \(String(format: "%.2f", result.duration))s")

            // Wait a moment for subscribers to receive the exit signal
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms

            // Cancel subscriber tasks
            for task in subscriberTasks {
                task.cancel()
            }

            print("\n✅ Global stream test completed")
        }
    }
}
