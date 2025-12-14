import CLIKit
import Foundation

/// Bash CLI program for running shell commands
@CLIProgram("/bin/bash")
public struct BashShell {

    /// Run a shell command with -c flag
    @CLICommand("-c")
    public struct Command {
        /// The shell command to execute
        @Positional public var script: String
    }
}

/// Homebrew installation commands (shell scripts)
public enum Homebrew {

    /// Install Homebrew using the official install script
    public static func installCommand() -> BashShell.Command {
        BashShell.Command(script: "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)")
    }

    /// Uninstall Homebrew using the official uninstall script
    public static func uninstallCommand() -> BashShell.Command {
        BashShell.Command(script: "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)")
    }
}
