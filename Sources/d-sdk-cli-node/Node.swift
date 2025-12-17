import CLISDK
import Foundation

/// Node.js CLI program definition using macro-based API
@CLIProgram
public struct Node {

    // MARK: - Version

    /// node --version command
    /// Example: node --version
    @CLICommand("--version")
    public struct Version {
        public init() {}
    }
}
