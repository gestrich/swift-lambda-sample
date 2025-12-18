# Workflow Role Exploration

**Status:** Exploratory
**Created:** 2025-12-17
**Related:** [workflow-protocol.md](workflow-protocol.md), [layered-architecture.md](../architecture/layered-architecture.md)

## Problem Statement

The original goal of workflows was to **break up massive services into smaller, focused pieces**. However, in practice:

1. Workflows became thin pass-through layers
2. Most logic still lives in services
3. Workflows mainly add `AsyncThrowingStream` boilerplate and progress yielding
4. We now have two layers (Workflow + Service) where one might suffice

### Current Architecture

```
App → Workflow (thin) → Service (has the logic) → SDK
```

### Example: XcodeBuildWorkflow

```swift
func run(options: Options) -> AsyncThrowingStream<Progress, Error> {
    AsyncThrowingStream { continuation in
        Task {
            continuation.yield(Progress(step: .cleaning))
            continuation.yield(Progress(step: .building))

            try await service.build(...)           // ← delegates
            let path = try await service.getExecutablePath()  // ← delegates

            continuation.yield(Progress(step: .complete))
            continuation.finish()
        }
    }
}
```

**What the workflow does:**
- Progress reporting structure
- Sequencing of service calls
- AsyncThrowingStream boilerplate

**What the workflow doesn't do:**
- Actual build logic (lives in service)
- Docker/Swift interactions (lives in SDK)

---

## Goals

1. **Clarify the role** of the layer between App and SDK
2. **Reduce unnecessary layering** where it adds no value
3. **Keep it lightweight** - avoid over-engineering
4. **Preserve progress reporting** where needed for UI

---

## Option A: Collapse Workflow + Service

**Concept:** Merge workflows and services into a single layer. The "Workflow" becomes the logic layer, not a thin orchestrator.

### Structure

```
App → Workflow (has the logic) → SDK
```

Services are eliminated or reduced to just models/configuration.

### Example

```swift
// Before: Two layers
struct XcodeBuildWorkflow {
    let service: XcodeLocalDevelopmentService

    func run() -> AsyncThrowingStream<Progress, Error> {
        // yields progress, delegates to service
        try await service.build(...)
    }
}

struct XcodeLocalDevelopmentService {
    func build() async throws {
        // actual logic here
    }
}

// After: One layer
struct XcodeBuildWorkflow {
    let swiftClient: SwiftBuildClient
    let dockerClient: DockerClient

    func run() -> AsyncThrowingStream<Progress, Error> {
        // yields progress AND contains logic
        try await swiftClient.build(target: "LambdaApp")
    }
}
```

### Pros
- One layer instead of two
- Clear ownership of logic
- Workflows become meaningful, not pass-through

### Cons
- Workflows get larger
- Harder to reuse logic across workflows (was in shared service)
- Testing workflows requires mocking SDKs

### When to Use
- When service methods map 1:1 to workflows anyway
- When the "service" is just grouping SDK calls

---

## Option B: Use Cases (Clean Architecture, Lightweight)

**Concept:** Replace workflows with simple "Operations" or "Use Cases". No streaming baked in. Progress becomes an optional, separate concern.

### Structure

```
App → Operation (logic, no streaming) → SDK
```

### Example

```swift
struct BuildLambdaOperation {
    private let swiftClient: SwiftBuildClient

    func execute(clean: Bool) async throws -> BuildResult {
        if clean {
            try await swiftClient.clean()
        }
        return try await swiftClient.build(target: "LambdaApp")
    }
}
```

### Progress as Optional Parameter

```swift
struct BuildLambdaOperation {
    func execute(
        clean: Bool,
        progress: ((BuildStep) -> Void)? = nil
    ) async throws -> BuildResult {
        progress?(.cleaning)
        if clean { try await swiftClient.clean() }

        progress?(.building)
        let result = try await swiftClient.build(target: "LambdaApp")

        progress?(.complete)
        return result
    }
}
```

### Stream Wrapper (If Needed)

```swift
// For callers that want AsyncThrowingStream
extension BuildLambdaOperation {
    func stream(clean: Bool) -> AsyncThrowingStream<BuildStep, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await execute(clean: clean) { step in
                        continuation.yield(step)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

### Pros
- Simple, focused operations
- No forced streaming - caller decides
- Logic clearly lives in the operation
- Easy to test (no stream complexity)

### Cons
- Progress callback pattern is less elegant than streams
- Need to decide on progress API (callback vs actor vs stream wrapper)
- Two ways to call (execute vs stream) might confuse

### When to Use
- When most callers don't need streaming
- When operations are truly single-purpose
- When you want maximum flexibility

---

## Option C: Keep Services, Eliminate Workflows

**Concept:** Workflows aren't needed. Services with focused methods are sufficient. If streaming is needed, add it at the call site.

### Structure

```
App → Service (logic) → SDK
```

### Example

```swift
struct LocalDevelopmentService {
    func build(clean: Bool) async throws -> BuildResult {
        // logic here
    }

    func startLambda() async throws { ... }
    func stopLambda() async throws { ... }
    func startServices() async throws { ... }
}
```

### Streaming at Call Site

```swift
// In CLI command
func run() async throws {
    print("Building...")
    let result = try await service.build(clean: options.clean)
    print("Complete: \(result.path)")
}

// In SwiftUI model, if streaming needed
func build() {
    Task {
        state = .building
        do {
            let result = try await service.build(clean: true)
            state = .complete(result)
        } catch {
            state = .failed(error)
        }
    }
}
```

### Pros
- Simplest option - removes a layer entirely
- Services are already written
- No migration needed for service logic

### Cons
- Services might bloat again over time (original problem)
- Progress reporting becomes ad-hoc
- No standard pattern for streaming

### When to Use
- When services are already well-factored
- When progress reporting isn't critical
- When you want minimal architecture

---

## Option D: Thin Operations + Generic Stream Wrapper

**Concept:** Separate concerns completely. Operations are pure logic. Streaming is a composable wrapper.

### Structure

```
App → StreamWrapper<Operation> → Operation (logic) → SDK
```

### Example

```swift
// Pure operation - no streaming knowledge
protocol Operation {
    associatedtype Input
    associatedtype Output
    func execute(input: Input) async throws -> Output
}

struct BuildOperation: Operation {
    func execute(input: BuildOptions) async throws -> BuildResult {
        // pure logic, no progress callbacks
    }
}

// Generic stream wrapper
struct ProgressStream<O: Operation> {
    let operation: O
    let steps: [String]  // or however progress is defined

    func run(input: O.Input) -> AsyncThrowingStream<Progress<O.Output>, Error> {
        // wraps operation execution with progress
    }
}
```

### Pros
- Maximum separation of concerns
- Operations stay pure and testable
- Streaming is opt-in and composable

### Cons
- More abstract / harder to understand
- Progress points not obvious from operation code
- May be over-engineered for the need

### When to Use
- When you want maximum composability
- When operations are truly independent of progress
- When you have many operations that need similar streaming

---

## Comparison Matrix

| Aspect | A: Collapse | B: Use Cases | C: Kill Workflows | D: Stream Wrapper |
|--------|-------------|--------------|-------------------|-------------------|
| **Layers** | App→Workflow→SDK | App→Operation→SDK | App→Service→SDK | App→Wrapper→Op→SDK |
| **Where logic lives** | Workflow | Operation | Service | Operation |
| **Streaming** | Built into workflow | Optional callback/wrapper | Ad-hoc at call site | Generic wrapper |
| **Complexity** | Medium | Low-Medium | Low | High |
| **Migration effort** | High (move logic) | Medium (refactor) | Low (delete workflows) | High (new abstraction) |
| **Progress reporting** | First-class | Optional | Manual | Composable |

---

## Questions to Consider

1. **How important is streaming/progress?**
   - If critical for UI: Options A, B (with wrapper), or D
   - If nice-to-have: Options B or C

2. **Where should logic live?**
   - If workflows should have it: Option A
   - If a middle layer should have it: Options B or D
   - If services are fine: Option C

3. **How much refactoring appetite?**
   - Minimal: Option C
   - Moderate: Option B
   - Significant: Options A or D

4. **What's the testing story?**
   - Options B and D are easiest to unit test (pure logic)
   - Option A requires mocking SDKs
   - Option C depends on service design

---

## Recommendation

**TBD** - Pending discussion of the tradeoffs above.

Initial instinct: **Option B (Use Cases)** offers a good balance:
- Lightweight and focused
- Logic has a clear home
- Progress is optional, not forced
- Easy to test
- Stream wrapper available when needed

But this depends on how critical streaming/progress is to the Mac app and CLI experiences.
