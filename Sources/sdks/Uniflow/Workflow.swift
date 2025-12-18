/// A workflow that executes and returns a final result.
public protocol Workflow: Sendable {
    /// Configuration options for the workflow (use Void for no options)
    associatedtype Options: Sendable = Void

    /// The final result type returned by `run()`
    associatedtype Result: Sendable

    /// Execute the workflow and return the final result
    func run(options: Options) async throws -> Result
}

// MARK: - Workflow Extensions

/// Convenience method for workflows with no options
extension Workflow where Options == Void {
    public func run() async throws -> Result {
        try await run(options: ())
    }
}
