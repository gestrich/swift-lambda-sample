import Testing
@testable import CLIKit

// Test command ID for consistent testing
private let testCommandID = CommandID()

// Helper to check StreamOutput values
private func isCommand(_ output: StreamOutput, _ expected: String) -> Bool {
    if case .command(_, let text) = output { return text == expected }
    return false
}

private func isStdout(_ output: StreamOutput, _ expected: String) -> Bool {
    if case .stdout(_, let text) = output { return text == expected }
    return false
}

private func isStderr(_ output: StreamOutput, _ expected: String) -> Bool {
    if case .stderr(_, let text) = output { return text == expected }
    return false
}

private func isExit(_ output: StreamOutput, _ expected: Int32) -> Bool {
    if case .exit(_, let code) = output { return code == expected }
    return false
}

@Suite("CLIOutputStream Tests")
struct CLIOutputStreamTests {

    @Test("Single subscriber receives output")
    func testSingleSubscriber() async {
        let output = CLIOutputStream()

        // Start subscriber
        let task = Task {
            var received: [StreamOutput] = []
            for await item in await output.makeStream() {
                received.append(item)
                if case .exit = item { break }
            }
            return received
        }

        // Give subscriber time to register
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Send output
        let cmdID = CommandID()
        await output.send(.stdout(commandID: cmdID, text: "hello"))
        await output.send(.stderr(commandID: cmdID, text: "error"))
        await output.send(.exit(commandID: cmdID, code: 0))

        let received = await task.value

        #expect(received.count == 3)
        #expect(isStdout(received[0], "hello"))
        #expect(isStderr(received[1], "error"))
        #expect(isExit(received[2], 0))
    }

    @Test("Multiple subscribers each receive all output")
    func testMultipleSubscribers() async {
        let output = CLIOutputStream()

        // Start two subscribers
        let task1 = Task {
            var received: [StreamOutput] = []
            for await item in await output.makeStream() {
                received.append(item)
                if case .exit = item { break }
            }
            return received
        }

        let task2 = Task {
            var received: [StreamOutput] = []
            for await item in await output.makeStream() {
                received.append(item)
                if case .exit = item { break }
            }
            return received
        }

        // Give subscribers time to register
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Send output
        let cmdID = CommandID()
        await output.send(.stdout(commandID: cmdID, text: "message"))
        await output.send(.exit(commandID: cmdID, code: 0))

        let received1 = await task1.value
        let received2 = await task2.value

        // Both should receive the same messages
        #expect(received1.count == 2)
        #expect(received2.count == 2)
        #expect(isStdout(received1[0], "message"))
        #expect(isStdout(received2[0], "message"))
    }

    @Test("Subscriber count tracks active subscribers")
    func testSubscriberCount() async {
        let output = CLIOutputStream()

        #expect(await output.subscriberCount == 0)

        // Start a subscriber
        let task = Task {
            for await item in await output.makeStream() {
                if case .exit = item { break }
            }
        }

        // Give subscriber time to register
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        #expect(await output.subscriberCount == 1)

        // End the stream
        let cmdID = CommandID()
        await output.send(.exit(commandID: cmdID, code: 0))
        await task.value

        // Give time for cleanup
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        #expect(await output.subscriberCount == 0)
    }

    @Test("Late subscriber only receives future output")
    func testLateSubscriber() async {
        let output = CLIOutputStream()

        // Send before any subscriber
        let missedCmdID = CommandID()
        await output.send(.stdout(commandID: missedCmdID, text: "missed"))

        // Now subscribe
        let task = Task {
            var received: [StreamOutput] = []
            for await item in await output.makeStream() {
                received.append(item)
                if case .exit = item { break }
            }
            return received
        }

        // Give subscriber time to register
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Send after subscriber
        let cmdID = CommandID()
        await output.send(.stdout(commandID: cmdID, text: "received"))
        await output.send(.exit(commandID: cmdID, code: 0))

        let received = await task.value

        // Should only have the messages sent after subscribing
        #expect(received.count == 2)
        #expect(isStdout(received[0], "received"))
    }

    @Test("finishAll closes all streams")
    func testFinishAll() async {
        let output = CLIOutputStream()

        let task1 = Task {
            var count = 0
            for await _ in await output.makeStream() {
                count += 1
            }
            return count
        }

        let task2 = Task {
            var count = 0
            for await _ in await output.makeStream() {
                count += 1
            }
            return count
        }

        // Give subscribers time to register
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        #expect(await output.subscriberCount == 2)

        // Send one message then finish
        let cmdID = CommandID()
        await output.send(.stdout(commandID: cmdID, text: "test"))
        await output.finishAll()

        // Wait for tasks to complete - they should exit when stream finishes
        let count1 = await task1.value
        let count2 = await task2.value

        #expect(count1 == 1)
        #expect(count2 == 1)
        #expect(await output.subscriberCount == 0)
    }
}
