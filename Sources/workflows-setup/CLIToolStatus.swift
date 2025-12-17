/// Status of a CLI tool dependency
public struct CLIToolStatus: Sendable, Equatable {
    public let tool: CLITool
    public let isInstalled: Bool
    public let version: String?

    public init(tool: CLITool, isInstalled: Bool, version: String? = nil) {
        self.tool = tool
        self.isInstalled = isInstalled
        self.version = version
    }
}
