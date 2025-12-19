/// A use case that yields state updates during execution via streaming.
/// Conforms to UseCase, providing run() via a default implementation that consumes the stream.
public protocol StreamingUseCase: UseCase {
    /// The type of state updates yielded during execution
    associatedtype State: Sendable

    /// Execute the use case, streaming state updates
    func stream(options: Options) -> AsyncThrowingStream<State, Error>
}

// MARK: - StreamingUseCase Extensions

/// Default run() implementation when Result == State (returns last state from stream)
extension StreamingUseCase where Result == State {
    public func run(options: Options) async throws -> Result {
        var lastState: State?
        for try await state in stream(options: options) {
            lastState = state
        }
        guard let result = lastState else {
            throw UseCaseError.noStateYielded
        }
        return result
    }
}

/// Convenience methods for streaming use cases with no options
extension StreamingUseCase where Options == Void {
    public func stream() -> AsyncThrowingStream<State, Error> {
        stream(options: ())
    }
}
