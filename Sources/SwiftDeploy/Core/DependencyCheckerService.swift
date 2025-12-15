import CLIKit
import Foundation

/// Stateless service for checking dependency installation status
public actor DependencyCheckerService {
    private let cliService: CLIService

    public init(cliService: CLIService) {
        self.cliService = cliService
    }

    // MARK: - Public API

    /// Check if a dependency is installed by running a command
    /// - Parameters:
    ///   - command: The command to check (e.g., "brew", "docker")
    ///   - versionArgs: Arguments to get version (e.g., ["--version"])
    /// - Returns: Installation status with version if installed
    public func checkDependency(_ command: String, versionArgs: [String] = ["--version"]) async -> DependencyInstallStatus {
        do {
            let result = try await cliService.execute(
                command: command,
                arguments: versionArgs,
                printCommand: false
            )

            if result.isSuccess {
                let version = result.stdout
                    .components(separatedBy: .newlines)
                    .first?
                    .trimmingCharacters(in: .whitespaces)
                return .installed(version: version)
            } else {
                return .notInstalled
            }
        } catch {
            return .notInstalled
        }
    }

    /// Check Homebrew installation status
    public func checkHomebrew() async -> DependencyInstallStatus {
        await checkDependency("brew")
    }

    /// Check Node.js installation status
    public func checkNodeJS() async -> DependencyInstallStatus {
        await checkDependency("node")
    }

    /// Check Docker installation status
    public func checkDocker() async -> DependencyInstallStatus {
        await checkDependency("docker")
    }

    /// Check AWS CLI installation status
    public func checkAWSCLI() async -> DependencyInstallStatus {
        await checkDependency("aws")
    }

    /// Check CDK installation status
    public func checkCDK() async -> DependencyInstallStatus {
        await checkDependency("cdk")
    }

    /// Check GitHub CLI installation status
    public func checkGitHubCLI() async -> DependencyInstallStatus {
        await checkDependency("gh")
    }
}

/// Installation status for a dependency
public enum DependencyInstallStatus: Equatable, Sendable {
    case unknown
    case checking
    case installed(version: String?)
    case notInstalled

    public var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }

    public var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }
}
