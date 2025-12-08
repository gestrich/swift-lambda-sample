# Plan: Refactor to Fresh Stream Per Subscriber Pattern

## Goal

Replace the custom `BroadcastAsyncSequence` with the more conventional "fresh stream per subscriber" pattern used by Apple's NotificationCenter.

## Current vs Proposed

| Aspect | Current (BroadcastAsyncSequence) | Proposed (Fresh Stream Per Subscriber) |
|--------|----------------------------------|----------------------------------------|
| Pattern | Custom `AsyncSequence` conformance | Factory method returning `AsyncStream` |
| Complexity | Higher (custom iterator, UUID tracking) | Lower (uses only built-in `AsyncStream`) |
| Convention | Less common | Apple's standard pattern (NotificationCenter) |
| Type | `BroadcastAsyncSequence<StreamOutput>` | `AsyncStream<StreamOutput>` |

## Implementation Steps

### Step 1: Create CLIOutputStream Class

Replace `BroadcastAsyncSequence` with a new `CLIOutputStream` class that creates fresh streams per subscriber.

**File:** `Sources/CLIKit/CLIOutputStream.swift` (new file)

```swift
import Foundation

/// A multi-subscriber output stream for CLI operations.
/// Each call to `makeStream()` creates an independent AsyncStream that receives all future output.
/// This follows the same pattern as NotificationCenter.notifications().
@MainActor
public final class CLIOutputStream: Sendable {
    private var continuations: [UUID: AsyncStream<StreamOutput>.Continuation] = [:]

    public init() {}

    /// Create a new stream for a subscriber.
    /// Each subscriber gets their own independent stream.
    /// The stream receives all output from the point of subscription forward.
    public func makeStream() -> AsyncStream<StreamOutput> {
        let id = UUID()

        return AsyncStream { continuation in
            // Register this subscriber
            self.continuations[id] = continuation

            // Clean up when consumer stops iterating
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    /// Send output to all active subscribers
    public func send(_ output: StreamOutput) {
        for continuation in continuations.values {
            continuation.yield(output)
        }
    }

    /// Finish all active streams (optional - for cleanup)
    public func finishAll() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    /// Number of active subscribers (useful for debugging)
    public var subscriberCount: Int {
        continuations.count
    }
}
```

### Step 2: Update CLIService

Replace `BroadcastAsyncSequence` usage with `CLIOutputStream`.

**File:** `Sources/CLIKit/CLIService.swift`

Changes:
```swift
// Before:
@MainActor
public static let globalOutput = BroadcastAsyncSequence<StreamOutput>()

// After:
@MainActor
public static let globalOutput = CLIOutputStream()
```

In `runProcess()`, change:
```swift
// Before:
Task { @MainActor in
    Self.globalOutput.yield(.stdout(text))
}

// After:
Task { @MainActor in
    Self.globalOutput.send(.stdout(text))
}
```

Same for `.stderr` and `.exit` calls.

### Step 3: Update StreamingTextView

The view already uses a closure-based approach. Update to call `makeStream()`.

**File:** `Sources/MacApp/StreamingTextView.swift`

The existing initializer signature:
```swift
init<S: AsyncSequence>(
    stream: S,
    onClear: (() -> Void)? = nil
) where S.Element == StreamOutput, S: Sendable, S.Failure == Never
```

This should continue to work since `AsyncStream<StreamOutput>` conforms to `AsyncSequence`.

### Step 4: Update SettingsView

Change from iterating over `CLIService.globalOutput` directly to calling `makeStream()`.

**File:** `Sources/MacApp/SettingsView.swift`

```swift
// Before:
StreamingTextView(stream: CLIService.globalOutput)

// After:
StreamingTextView(stream: CLIService.globalOutput.makeStream())
```

### Step 5: Delete BroadcastAsyncSequence

Remove the file since it's no longer needed.

**Delete:** `Sources/CLIKit/BroadcastAsyncSequence.swift`

### Step 6: Update Dev Test Command

Update the test command to use the new API.

**File:** `Sources/SwiftDeployCLI/Commands/Dev/TestGlobalStreamCommand.swift`

```swift
// Before:
for await output in CLIService.globalOutput { ... }

// After:
for await output in CLIService.globalOutput.makeStream() { ... }
```

## API Comparison

| Usage | Before | After |
|-------|--------|-------|
| Get stream | `CLIService.globalOutput` (is the sequence) | `CLIService.globalOutput.makeStream()` |
| Send output | `globalOutput.yield(.stdout(text))` | `globalOutput.send(.stdout(text))` |
| Iterate | `for await in globalOutput` | `for await in globalOutput.makeStream()` |

## Benefits

1. **Simpler implementation** - No custom `AsyncSequence` conformance needed
2. **Follows Apple convention** - Same pattern as NotificationCenter
3. **Clearer semantics** - `makeStream()` explicitly creates a new subscription
4. **Built-in types only** - Uses standard `AsyncStream`
5. **Easier to understand** - No UUID tracking in custom iterator

## Testing

After implementation:
1. Run `swift build` to verify compilation
2. Run `swift run SwiftDeployCLI dev test-global-stream` to verify multi-subscriber behavior
3. Test SettingsView in MacApp to verify UI receives output

## Files Changed

| File | Change |
|------|--------|
| `Sources/CLIKit/CLIOutputStream.swift` | **New** - Fresh stream per subscriber implementation |
| `Sources/CLIKit/CLIService.swift` | Update `globalOutput` type and calls |
| `Sources/CLIKit/BroadcastAsyncSequence.swift` | **Delete** |
| `Sources/MacApp/SettingsView.swift` | Call `.makeStream()` |
| `Sources/SwiftDeployCLI/Commands/Dev/TestGlobalStreamCommand.swift` | Call `.makeStream()` |
