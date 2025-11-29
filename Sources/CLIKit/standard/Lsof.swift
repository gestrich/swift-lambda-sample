import Foundation

/// lsof CLI program for listing open files and network connections
/// Usage: lsof -i :PORT [-t]
@CLIProgram
public struct Lsof {
    /// Port specification (e.g., ":8080")
    @Option("-i") public var port: String

    /// Only return PIDs (-t flag)
    @Flag("-t") public var pidOnly: Bool = false
}
