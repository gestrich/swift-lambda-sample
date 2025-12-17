/// A snapshot of all dependency statuses at a point in time
public struct DependencySnapshot: Sendable, Equatable {
    public let statuses: [CLITool: CLIToolStatus]

    public init(statuses: [CLITool: CLIToolStatus]) {
        self.statuses = statuses
    }

    /// Get the status for a specific tool
    public func status(for tool: CLITool) -> CLIToolStatus? {
        statuses[tool]
    }

    /// Check if all dependencies are installed
    public var allInstalled: Bool {
        CLITool.allCases.allSatisfy { statuses[$0]?.isInstalled == true }
    }
}
