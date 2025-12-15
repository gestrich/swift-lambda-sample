# Plan: Global CLI Output AsyncSequence

## Status

| Phase | Status | Notes |
|-------|--------|-------|
| Step 1: BroadcastAsyncSequence | ✅ Complete | Created `Sources/CLIKit/BroadcastAsyncSequence.swift` |
| Step 2: Unified Process Execution | ✅ Complete | Added `runProcess()`, `globalOutput`, `OutputAccumulator` |
| Step 3: StreamingTextView | ✅ Complete | Added async sequence initializer with closure-based type erasure |
| Step 4: SettingsView Integration | ✅ Complete | Updated SettingsView to use `CLIService.globalOutput` directly |

### Implementation Notes

**Step 1 & 2 (Completed 2024-11-30):**

- Created `BroadcastAsyncSequence<Element>` - a multi-consumer `AsyncSequence` using UUID-keyed continuations
- Added `OutputAccumulator` class for thread-safe string accumulation (avoids Sendable closure capture issues)
- Unified `executeProcessInternal` and `streamProcess` into single `runProcess()` method
- All CLI output now broadcasts to `CLIService.globalOutput` automatically
- Added dev test command: `swift run SwiftDeployCLI dev test-global-stream`

**Step 3 (Completed 2024-11-30):**

- Updated `StreamingTextView` to support two modes: static lines and async sequence consumption
- Added `typealias Failure = Never` to `BroadcastAsyncSequence` for Swift 6 typed throws compatibility
- Used closure-based type erasure pattern to avoid SwiftUI generic view complexity:
  - Store a `@Sendable` closure that captures the stream iteration logic
  - Closure calls back to `@MainActor` for each `StreamOutput` received
  - Allows `StreamingTextView` to remain non-generic while accepting any `AsyncSequence<StreamOutput, Never>`
- Added `CLIKit` as direct dependency of `MacApp` target
- Key constraint: `S.Failure == Never` ensures non-throwing async sequences only

**Step 4 (Completed 2024-11-30):**

- Simplified `SettingsView.unifiedOutputSection` to use `CLIService.globalOutput` directly
- Removed dependency on `model.unifiedOutput` (the old `UnifiedOutputState`-based approach)
- Added `import CLIKit` to SettingsView for access to `CLIService.globalOutput`
- Enhanced `StreamingTextView` Clear button to reset internal `liveLines` state in stream mode
  - Button now shows for stream mode even without explicit `onClear` callback
  - Clears local state first, then calls optional external callback
- The view now automatically subscribes to the global broadcast stream on appear

**Test Results:**
```
🧪 Testing BroadcastAsyncSequence with global CLI output stream
   Subscribers: 2

📡 Subscriber 1 started listening
📡 Subscriber 2 started listening

🚀 Running command: echo 'Hello from global stream test!'
→ /bin/echo 'Hello from global stream test!'
Hello from global stream test!
   [Sub 2] stdout: Hello from global stream test!
   [Sub 1] stdout: Hello from global stream test!

📊 Command result:
   Exit code: 0
   [Sub 2] exit: 0
   [Sub 1] exit: 0
   Duration: 0.01s

✅ Global stream test completed
```

---

## Terminology Clarification

**AsyncSequence** is a Swift protocol (like `Sequence`, but async). Types conforming to it can be iterated with `for await`:

```swift
protocol AsyncSequence {
    associatedtype Element
    func makeAsyncIterator() -> AsyncIterator
}
```

**AsyncStream** is Apple's concrete implementation of `AsyncSequence` - but it's single-consumer only.

**What we're building:** A custom type conforming to `AsyncSequence` that supports multiple concurrent consumers (broadcast pattern).

---

## Current Architecture

```
CLIService.stream(command) → AsyncStream<StreamOutput>
                                    ↓
                            Single consumer only
                                    ↓
                    Service iterates with "for await"
```

Each call to `stream()` creates an independent, single-use `AsyncStream` for that command.

---

## Proposed Architecture

```
CLIService
    │
    ├── stream(command) → AsyncStream<StreamOutput>     [KEEP - per-command, single consumer]
    │
    └── globalOutputStream → BroadcastAsyncSequence    [NEW - all output, multi-consumer]
                                    ↓
                    ┌───────────────┼───────────────┐
                    ↓               ↓               ↓
              Subscriber 1    Subscriber 2    Subscriber N
              (Service)       (UI View)       (Logger, etc)
```

**Key insight:** The existing `stream()` methods continue to work as-is. We add a *parallel* global stream that mirrors all output.

---

## How Both Streams Coexist

**Important:** Most CLI calls use `execute()` or `executeForResult()`, not `stream()`. We must broadcast from ALL execution paths.

### Solution

Unify `executeProcessInternal` and `streamProcess` into a single `runProcess()` method that:
- Always uses real-time output handling (`readabilityHandler`)
- Always broadcasts to global stream
- Optionally yields to per-command stream continuation
- Returns `ExecutionResult` with accumulated output

This ensures ALL CLI output goes through one code path and appears in the global stream.

---

## Implementation Steps

### Step 1: Create BroadcastAsyncSequence

A custom `AsyncSequence` that allows multiple subscribers.

**File:** `Sources/CLIKit/BroadcastAsyncSequence.swift`

```swift
/// An AsyncSequence that broadcasts elements to multiple concurrent subscribers.
/// Each subscriber receives elements from the point they subscribe forward.
@MainActor
public final class BroadcastAsyncSequence<Element: Sendable>: AsyncSequence {
    public typealias AsyncIterator = Iterator

    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    public init() {}

    /// Broadcast an element to all current subscribers
    public func yield(_ element: Element) {
        for continuation in continuations.values {
            continuation.yield(element)
        }
    }

    /// Signal completion to all subscribers
    public func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(parent: self)
    }

    public struct Iterator: AsyncIteratorProtocol {
        private let id = UUID()
        private var streamIterator: AsyncStream<Element>.Iterator
        private let parent: BroadcastAsyncSequence

        init(parent: BroadcastAsyncSequence) {
            self.parent = parent

            var capturedContinuation: AsyncStream<Element>.Continuation?
            let stream = AsyncStream<Element> { continuation in
                capturedContinuation = continuation
            }

            // Register with parent
            if let continuation = capturedContinuation {
                parent.continuations[id] = continuation

                continuation.onTermination = { @Sendable _ in
                    Task { @MainActor in
                        parent.continuations.removeValue(forKey: id)
                    }
                }
            }

            self.streamIterator = stream.makeAsyncIterator()
        }

        public mutating func next() async -> Element? {
            await streamIterator.next()
        }
    }
}
```

### Step 2: Unify Process Execution & Add Global Stream

Currently there are two similar methods with duplication:

| Method | Output Handling | Returns |
|--------|----------------|---------|
| `executeProcessInternal` | Batch (reads all at end) | `ExecutionResult` |
| `streamProcess` | Real-time (`readabilityHandler`) | Yields to continuation |

**Unify into single method** that always streams in real-time:

**File:** `Sources/CLIKit/CLIService.swift`

```swift
public actor CLIService {
    /// Global output stream - broadcasts all CLI output to any subscriber
    @MainActor
    public static let globalOutput = BroadcastAsyncSequence<StreamOutput>()

    /// Unified process execution - always streams output in real-time
    /// - Parameters:
    ///   - command: Executable path
    ///   - arguments: Command arguments
    ///   - workingDirectory: Working directory
    ///   - environment: Environment variables
    ///   - timeout: Optional timeout
    ///   - inheritIO: If true, inherit stdin/stdout/stderr (no capture)
    ///   - commandContinuation: Optional per-command stream continuation
    /// - Returns: ExecutionResult with accumulated stdout/stderr
    private func runProcess(
        command: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        timeout: TimeInterval?,
        inheritIO: Bool,
        commandContinuation: AsyncStream<StreamOutput>.Continuation?
    ) throws -> ExecutionResult {
        let startTime = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.environment = environment

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        // Accumulators for ExecutionResult
        var stdoutAccumulator = ""
        var stderrAccumulator = ""

        let outputPipe: Pipe?
        let errorPipe: Pipe?

        if inheritIO {
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            outputPipe = nil
            errorPipe = nil
        } else {
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            outputPipe = outPipe
            errorPipe = errPipe

            // Real-time output handling (always)
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    stdoutAccumulator += text
                    print(text, terminator: "")

                    // Yield to per-command stream (if provided)
                    commandContinuation?.yield(.stdout(text))

                    // Broadcast to global stream
                    Task { @MainActor in
                        Self.globalOutput.yield(.stdout(text))
                    }
                }
            }

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    stderrAccumulator += text
                    print(text, terminator: "")

                    commandContinuation?.yield(.stderr(text))

                    Task { @MainActor in
                        Self.globalOutput.yield(.stderr(text))
                    }
                }
            }
        }

        // Timeout handling
        var timeoutTask: Task<Void, Never>?
        if let timeout {
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
            }
        }

        try process.run()
        process.waitUntilExit()

        timeoutTask?.cancel()

        // Clean up handlers
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        let exitCode = process.terminationStatus
        let duration = Date().timeIntervalSince(startTime)

        // Yield exit to streams
        commandContinuation?.yield(.exit(exitCode))
        commandContinuation?.finish()

        Task { @MainActor in
            Self.globalOutput.yield(.exit(exitCode))
        }

        // Check timeout
        if let timeout, duration >= timeout && exitCode != 0 {
            throw CLIClientError.timeout(
                command: "\(command) \(arguments.joined(separator: " "))",
                duration: timeout
            )
        }

        return ExecutionResult(
            exitCode: exitCode,
            stdout: stdoutAccumulator,
            stderr: stderrAccumulator,
            duration: duration
        )
    }
}
```

**Then simplify callers:**

```swift
// executeProcessInternal becomes:
private func executeProcessInternal(...) throws -> ExecutionResult {
    try runProcess(
        command: command,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        timeout: timeout,
        inheritIO: inheritIO,
        commandContinuation: nil  // No per-command stream
    )
}

// streamProcess becomes:
private func streamProcess(..., continuation: ...) throws {
    _ = try runProcess(
        command: command,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        timeout: nil,
        inheritIO: false,
        commandContinuation: continuation  // Per-command stream
    )
}
```

**Benefits:**
- Single source of truth for process execution
- All output automatically broadcasts to global stream
- Real-time streaming for ALL commands (not just `stream()` calls)
- Existing API unchanged

### Step 3: Update StreamingTextView

Add ability to consume an `AsyncSequence` directly.

**File:** `Sources/MacApp/StreamingTextView.swift`

```swift
struct StreamingTextView<S: AsyncSequence>: View where S.Element == StreamOutput {
    // For static lines (existing)
    private let staticLines: [String]?

    // For live stream (new)
    private let stream: S?

    @State private var liveLines: [String] = []

    // Existing initializer for static lines
    init(lines: [String], isClearDisabled: Bool = false, onClear: (() -> Void)? = nil) {
        self.staticLines = lines
        self.stream = nil
        // ...
    }

    // New initializer for async sequence
    init(stream: S, onClear: (() -> Void)? = nil) {
        self.staticLines = nil
        self.stream = stream
        // ...
    }

    private var displayLines: [String] {
        staticLines ?? liveLines
    }

    var body: some View {
        // Existing view code using displayLines...
        .task {
            guard let stream = stream else { return }
            for await output in stream {
                await processOutput(output)
            }
        }
    }

    @MainActor
    private func processOutput(_ output: StreamOutput) {
        switch output {
        case .stdout(let text), .stderr(let text):
            appendText(text)
        case .exit, .error:
            break
        }
    }
}
```

### Step 4: Update SettingsView

**File:** `Sources/MacApp/SettingsView.swift`

```swift
private var unifiedOutputSection: some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Text("Output")
                .font(.headline)
            // ...
        }

        // Use global stream directly
        StreamingTextView(stream: CLIService.globalOutput)
    }
}
```

---

## API Comparison

| Use Case | Before | After |
|----------|--------|-------|
| Run command, process output | `for await in cliService.stream(cmd)` | Same (unchanged) |
| Watch all CLI output | Not possible | `for await in CLIService.globalOutput` |
| UI display | Observe `[String]` array | Consume `AsyncSequence` directly |

---

## What Changes, What Stays

**Unchanged:**
- `CLIService.stream(command)` methods
- `StreamOutput` enum
- Per-command streaming behavior
- Existing service code that consumes streams

**New:**
- `BroadcastAsyncSequence` type
- `CLIService.globalOutput` static property
- `StreamingTextView` async sequence initializer

---

## Open Questions

1. **Clear behavior:** When user taps "Clear", should it:
   - Just clear the view's local `@State` array?
   - Signal something to the broadcast sequence?

2. **Lifetime:** `globalOutput` is static/singleton. Should it ever be reset?

3. **Back-pressure:** If UI can't keep up, elements queue in the AsyncStream. Is this acceptable?
