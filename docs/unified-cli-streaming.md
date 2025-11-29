# Unified CLI Streaming

## Overview

Simplify CLI output handling by having a single CLIService that collects all command output and exposes one stream for UI consumption.

## Current State

- `CLIService.stream()` returns per-call `AsyncStream<StreamOutput>`
- Individual state objects (`BuildState`, `LambdaState`) with `appendOutput()`
- Services manually iterate streams and forward to state objects
- Multiple output views (`BuildOutputView`, `LambdaOutputView`)

## Proposed Design

### CLIService as Central Collector

```
CLIService (singleton)
├── Runs all commands
├── Publishes ALL output to a single AsyncStream<StreamOutput>
├── Maintains outputLines: [String] for UI binding
└── One subscription point - clients observe, don't control
```

**Key point**: The async stream publishes output from **every** CLI call automatically. Clients subscribe to observe output—they don't control what gets streamed. All CLI execution flows through this single stream.

### Stream Output Type

The stream uses an enum to distinguish commands from their output, with a shared identifier to associate output with its command:

```swift
/// Unique identifier for a CLI command execution
struct CLICommandID: Hashable {
    let id: UUID
}

enum CLIStreamItem {
    case command(id: CLICommandID, command: String)  // The command being executed
    case output(id: CLICommandID, line: String)      // stdout/stderr line from the command
}
```

**Benefits of command ID:**
- Group output lines by their originating command
- Filter/display output from specific commands differently
- Handle interleaved output from concurrent commands
- UI can collapse/expand output per command

### Two Streaming APIs

```swift
// 1. Per-call stream (existing) - for callers who need output from a specific command
func stream(_ arguments: [String]) -> AsyncThrowingStream<String, Error>

// 2. Unified stream (new) - publishes ALL CLI output
var unifiedStream: AsyncStream<CLIStreamItem>
```

- **Per-call stream**: Returns output for that specific command only. Existing API, unchanged.
- **Unified stream**: Publishes everything (commands + output) from all CLI calls. New addition.

Both work simultaneously—the unified stream observes all activity while per-call streams still work for callers who need isolated output.

### Single Output View

```
UI
└── One StreamingTextView bound to CLIService.outputItems
```

## Implementation Plan

### 1. Update CLIService

- Add `CLIStreamItem` enum with `.command(String)` and `.output(String)` cases
- Add `outputItems: [CLIStreamItem]` property (observable)
- Add private continuation for unified streaming
- Add `unifiedStream: AsyncStream<CLIStreamItem>` property
- Keep existing `stream()` method unchanged (per-call streams still work)
- Modify internal execution to:
  - Yield to per-call stream (existing behavior)
  - Also yield to unified stream (`.command(...)` before, `.output(...)` for each line)
- Add `clear()` method

### 2. Remove Per-Service State

- Remove `BuildState` class (or repurpose for status only, no output)
- Remove `LambdaState` class (or repurpose for status only, no output)
- Remove `lambdaState` from `LambdaService` protocol
- Update services to remove output-related code

### 3. Simplify UI

- Remove `BuildOutputView`
- Remove `LambdaOutputView`
- Add single `CLIOutputView` in `SettingsView`
- Bind to `CLIService.shared.outputLines`

### 4. Keep Status Separate

Build and Lambda status (building/success/failed, running/stopped) remain separate from output:

```swift
// Status only, no output
enum BuildStatus { case notBuilt, building, success, failed }
enum LambdaStatus { case stopped, starting, running, failed }
```

## Open Questions

1. **Clearing** - When to clear output?
   - Manual clear button only
   - Clear on each new operation
   - Rolling buffer (e.g., last 1000 lines)

2. **Concurrent operations** - Output interleaves if multiple operations run. Acceptable?

3. **Filtering** - Need to filter by operation type? Or is unified stream sufficient?

4. **Multiple consumers** - `AsyncStream` is single-consumer (values are consumed once). Options:
   - Bind multiple UI components to `outputItems` array (recommended for UI)
   - Use `AsyncBroadcastSequence` or similar for multiple stream consumers
   - Have one consumer that redistributes to others

## Benefits

- Single source of truth for CLI output
- No scope passing or collector management
- Simpler service code (just call CLIService)
- One output view to maintain
- CLIService already exists as shared singleton

## Migration Steps

1. Add output collection to CLIService
2. Create CLIOutputView
3. Update SettingsView to use CLIOutputView
4. Remove BuildState output logic (keep status)
5. Remove LambdaState output logic (keep status)
6. Remove old output views
7. Clean up services
