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
    /// Example: npm install -g aws-cdk
    @CLICommand
    public struct Install {
        /// Install globally
        @Flag("-g") public var global: Bool = false

        /// Package to install (optional for project dependencies)
        @Positional public var package: String?
    }

    // MARK: - Uninstall

    /// npm uninstall command
    /// Example: npm uninstall -g aws-cdk
    @CLICommand
    public struct Uninstall {
        /// Uninstall globally
        @Flag("-g") public var global: Bool = false

        /// Package to uninstall
        @Positional public var package: String
    }
}
