import CLISDK
import Foundation

/// Build script CLI wrapper for ./build.sh
/// The build script compiles Swift Lambda for AWS (linux/amd64) using Docker
@CLIProgram("./build.sh")
public struct BuildScript {
    public init() {}

    /// Build Lambda for Linux (Docker-based)
    /// Example: ./build.sh LambdaApp linux/amd64 $GITHUB_TOKEN
    @CLICommand("")
    public struct Build {
        /// Build target name (required, e.g., "LambdaApp")
        @Positional public var target: String

        /// Platform name (defaults to linux/amd64 for AWS Lambda x86_64)
        @Positional public var platform: String?

        /// GitHub token for private dependencies (optional)
        @Positional public var githubToken: String?
    }
}

// MARK: - Convenience Initializers

public extension BuildScript.Build {
    /// Create a build command for the default AWS Lambda platform (linux/amd64)
    /// - Parameter target: The build target name (e.g., "LambdaApp")
    static func lambda(target: String) -> Self {
        Self(target: target, platform: nil, githubToken: nil)
    }

    /// Create a build command with a specific platform
    /// - Parameters:
    ///   - target: The build target name (e.g., "LambdaApp")
    ///   - platform: The platform name (e.g., "linux/amd64", "linux/arm64")
    static func forPlatform(target: String, platform: String) -> Self {
        Self(target: target, platform: platform, githubToken: nil)
    }

    /// Create a build command with GitHub token for private dependencies
    /// - Parameters:
    ///   - target: The build target name (e.g., "LambdaApp")
    ///   - platform: The platform name (e.g., "linux/amd64")
    ///   - githubToken: GitHub token for private dependencies
    static func withToken(target: String, platform: String? = nil, githubToken: String) -> Self {
        Self(target: target, platform: platform, githubToken: githubToken)
    }
}
