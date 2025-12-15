import sdk_cli
import Foundation
import Observation
import service_deploy

/// Observable model for dependency installation status
/// Holds UI state and delegates checking to DependencyCheckerService
@MainActor
@Observable
public final class DependencyStatusModel {
    // MARK: - Status Properties

    public private(set) var homebrewStatus: DependencyInstallStatus = .unknown
    public private(set) var nodejsStatus: DependencyInstallStatus = .unknown
    public private(set) var dockerStatus: DependencyInstallStatus = .unknown
    public private(set) var awsCLIStatus: DependencyInstallStatus = .unknown
    public private(set) var cdkStatus: DependencyInstallStatus = .unknown
    public private(set) var githubCLIStatus: DependencyInstallStatus = .unknown

    // MARK: - Services

    public let cliClient: CLIClient
    private let checkerService: DependencyCheckerService

    // MARK: - Init

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
        self.checkerService = DependencyCheckerService(cliClient: cliClient)
    }

    // MARK: - Public API

    /// Check all dependency statuses
    public func checkAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.checkHomebrew() }
            group.addTask { await self.checkNodeJS() }
            group.addTask { await self.checkDocker() }
            group.addTask { await self.checkAWSCLI() }
            group.addTask { await self.checkCDK() }
            group.addTask { await self.checkGitHubCLI() }
        }
    }

    /// Check Homebrew installation status
    public func checkHomebrew() async {
        homebrewStatus = .checking
        homebrewStatus = await checkerService.checkHomebrew()
    }

    /// Check Node.js installation status
    public func checkNodeJS() async {
        nodejsStatus = .checking
        nodejsStatus = await checkerService.checkNodeJS()
    }

    /// Check Docker installation status
    public func checkDocker() async {
        dockerStatus = .checking
        dockerStatus = await checkerService.checkDocker()
    }

    /// Check AWS CLI installation status
    public func checkAWSCLI() async {
        awsCLIStatus = .checking
        awsCLIStatus = await checkerService.checkAWSCLI()
    }

    /// Check CDK installation status
    public func checkCDK() async {
        cdkStatus = .checking
        cdkStatus = await checkerService.checkCDK()
    }

    /// Check GitHub CLI installation status
    public func checkGitHubCLI() async {
        githubCLIStatus = .checking
        githubCLIStatus = await checkerService.checkGitHubCLI()
    }
}
