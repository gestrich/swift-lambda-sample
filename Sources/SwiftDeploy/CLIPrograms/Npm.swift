import CLIKit
import Foundation

/// npm CLI program definition using macro-based API
@CLIProgram
public struct Npm {

    // MARK: - Run

    /// npm run command
    /// Example: npm run build
    @CLICommand
    public struct Run {
        /// Script name to run (e.g., "build", "test")
        @Positional public var script: String
    }

    // MARK: - Install

    /// npm install command
    /// Example: npm install
    @CLICommand
    public struct Install {
        /// Optional package to install
        @Positional public var package: String?
    }
}
