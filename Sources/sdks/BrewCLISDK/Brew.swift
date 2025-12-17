import CLISDK
import Foundation

/// Homebrew CLI program definition using macro-based API
@CLIProgram
public struct Brew {

    // MARK: - Version

    /// brew --version command
    /// Example: brew --version
    @CLICommand("--version")
    public struct Version {
        public init() {}
    }

    // MARK: - Install

    /// brew install command
    /// Example: brew install --cask docker
    @CLICommand
    public struct Install {
        /// Install as a cask (macOS application)
        @Flag("--cask") public var cask: Bool = false

        /// Package name to install
        @Positional public var package: String
    }

    // MARK: - Uninstall

    /// brew uninstall command
    /// Example: brew uninstall --cask docker
    @CLICommand
    public struct Uninstall {
        /// Uninstall a cask (macOS application)
        @Flag("--cask") public var cask: Bool = false

        /// Package name to uninstall
        @Positional public var package: String
    }
}
