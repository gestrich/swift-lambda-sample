import Foundation

/// Lambda build artifact paths for different platforms.
/// Centralizes path knowledge for Linux (Docker) and Xcode (native) builds.
public struct LambdaPaths: Sendable {
    private let workingDirectory: String
    private let productName: String

    public init(workingDirectory: String, productName: String = "LambdaApp") {
        self.workingDirectory = workingDirectory
        self.productName = productName
    }

    // MARK: - Linux Build Paths

    /// Directory containing extracted Lambda files
    public var lambdaDir: String { "\(workingDirectory)/lambda" }

    /// Path to the Lambda bootstrap executable
    public var bootstrapPath: String { "\(lambdaDir)/bootstrap" }

    /// Path to the Lambda zip package
    public var lambdaZipPath: String { "\(workingDirectory)/lambda.zip" }

    /// AWS SAM build directory
    public var awsSamBuildDir: String { "\(workingDirectory)/.aws-sam/build-SwiftLambda" }

    /// Relative paths to clean when deleting Linux build artifacts
    public var linuxBuildArtifactRelativePaths: [String] {
        ["lambda", "lambda.zip", ".aws-sam/build-SwiftLambda"]
    }

    /// Check if Linux build artifacts exist
    public func isLinuxBuildComplete() -> Bool {
        FileManager.default.fileExists(atPath: lambdaDir) &&
        FileManager.default.fileExists(atPath: bootstrapPath) &&
        FileManager.default.fileExists(atPath: lambdaZipPath)
    }

    // MARK: - Xcode Build Paths

    /// Swift Package Manager build directory
    public var buildDir: String { "\(workingDirectory)/.build" }

    /// Find the path to the built Xcode executable, if it exists.
    /// Searches through architecture-specific subdirectories.
    public func xcodeBuildPath() -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: buildDir) else {
            return nil
        }
        for item in contents {
            let executablePath = "\(buildDir)/\(item)/debug/\(productName)"
            if FileManager.default.fileExists(atPath: executablePath) {
                return executablePath
            }
        }
        return nil
    }

    /// Check if Xcode build artifacts exist
    public func isXcodeBuildComplete() -> Bool {
        xcodeBuildPath() != nil
    }
}
