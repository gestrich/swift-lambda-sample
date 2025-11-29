import CLIKit
import Foundation

/// Swift CLI program definition using macro-based API
@CLIProgram("swift")
public struct SwiftCLI {

    // MARK: - Package Commands

    /// Swift package clean command
    /// Example: swift package clean
    @CLICommand("package clean")
    public struct PackageClean {
    }

    // MARK: - Build Commands

    /// Swift build command
    /// Example: swift build --product SwiftLambda --show-bin-path
    @CLICommand
    public struct Build {
        /// Build a specific product
        @Option public var product: String?

        /// Print the binary output path
        @Flag public var showBinPath: Bool = false
    }
}
