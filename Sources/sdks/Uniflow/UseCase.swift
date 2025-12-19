/// A use case that executes and returns a final result.
public protocol UseCase: Sendable {
    /// Configuration options for the use case (use Void for no options)
    associatedtype Options: Sendable = Void

    /// The final result type returned by `run()`
    associatedtype Result: Sendable

    /// Execute the use case and return the final result
    func run(options: Options) async throws -> Result
}

// MARK: - UseCase Extensions

/// Convenience method for use cases with no options
extension UseCase where Options == Void {
    public func run() async throws -> Result {
        try await run(options: ())
    }
}
