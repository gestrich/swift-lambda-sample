import sdk_cli
import Foundation

/// Swift CLI program definition using macro-based API
@CLIProgram("swift")
public struct SwiftCLI {

    // MARK: - Package Commands

    @CLICommand
    public struct Package {
        /// Swift package clean command
        /// Example: swift package clean
        @CLICommand
        public struct Clean {
        }
    }

    // MARK: - Build Commands

    /// Swift build command
    /// Example: swift build --product feature-lambda --show-bin-path
    @CLICommand
    public struct Build {
        /// Build a specific product
        @Option public var product: String?

        /// Print the binary output path
        @Flag public var showBinPath: Bool = false
    }
}
