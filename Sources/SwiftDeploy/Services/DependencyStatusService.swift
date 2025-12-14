import CLIKit
import Foundation
import Observation

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

/// Service for checking dependency installation status
@MainActor
@Observable
public final class DependencyStatusService {
    // MARK: - Status Properties

    public private(set) var dockerStatus: DependencyInstallStatus = .unknown
    public private(set) var awsCLIStatus: DependencyInstallStatus = .unknown
    public private(set) var cdkStatus: DependencyInstallStatus = .unknown
    public private(set) var githubCLIStatus: DependencyInstallStatus = .unknown

    // MARK: - Services

    public let cliService: CLIService

    // MARK: - Init

    public init(cliService: CLIService) {
        self.cliService = cliService
    }

    // MARK: - Public API

    /// Check all dependency statuses
    public func checkAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.checkDocker() }
            group.addTask { await self.checkAWSCLI() }
            group.addTask { await self.checkCDK() }
            group.addTask { await self.checkGitHubCLI() }
        }
    }

    /// Check Docker installation status
    public func checkDocker() async {
        dockerStatus = .checking
        dockerStatus = await checkCommand("docker", versionArgs: ["--version"])
    }

    /// Check AWS CLI installation status
    public func checkAWSCLI() async {
        awsCLIStatus = .checking
        awsCLIStatus = await checkCommand("aws", versionArgs: ["--version"])
    }

    /// Check CDK installation status
    public func checkCDK() async {
        cdkStatus = .checking
        cdkStatus = await checkCommand("cdk", versionArgs: ["--version"])
    }

    /// Check GitHub CLI installation status
    public func checkGitHubCLI() async {
        githubCLIStatus = .checking
        githubCLIStatus = await checkCommand("gh", versionArgs: ["--version"])
    }

    // MARK: - Private Helpers

    private func checkCommand(_ command: String, versionArgs: [String]) async -> DependencyInstallStatus {
        do {
            let result = try await cliService.execute(
                command: command,
                arguments: versionArgs,
                printCommand: false
            )

            if result.isSuccess {
                // Extract version from output (first line, trimmed)
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
}
