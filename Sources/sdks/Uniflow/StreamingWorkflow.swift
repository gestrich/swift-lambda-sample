/// A workflow that yields state updates during execution via streaming.
/// Conforms to Workflow, providing run() via a default implementation that consumes the stream.
public protocol StreamingWorkflow: Workflow {
    /// The type of state updates yielded during execution
    associatedtype State: Sendable

    /// Execute the workflow, streaming state updates
    func stream(options: Options) -> AsyncThrowingStream<State, Error>
}

// MARK: - StreamingWorkflow Extensions

/// Default run() implementation when Result == State (returns last state from stream)
extension StreamingWorkflow where Result == State {
    public func run(options: Options) async throws -> Result {
        var lastState: State?
        for try await state in stream(options: options) {
            lastState = state
        }
        guard let result = lastState else {
            throw WorkflowError.noStateYielded
        }
        return result
    }
}

/// Convenience methods for streaming workflows with no options
extension StreamingWorkflow where Options == Void {
    public func stream() -> AsyncThrowingStream<State, Error> {
        stream(options: ())
    }
}
