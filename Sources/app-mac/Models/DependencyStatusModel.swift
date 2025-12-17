import sdk_cli
import sdk_cli_brew
import sdk_cli_docker
import sdk_cli_node
import sdk_aws
import sdk_github
import Foundation
import Observation

/// Observable model for dependency installation status
/// Uses individual SDK clients for checking each dependency
@MainActor
@Observable
public final class DependencyStatusModel {
    // MARK: - Status Properties

    public private(set) var homebrewStatus: DependencyUIState = .unknown
    public private(set) var nodejsStatus: DependencyUIState = .unknown
    public private(set) var dockerStatus: DependencyUIState = .unknown
    public private(set) var awsCLIStatus: DependencyUIState = .unknown
    public private(set) var cdkStatus: DependencyUIState = .unknown
    public private(set) var githubCLIStatus: DependencyUIState = .unknown

    // MARK: - Clients

    public let cliClient: CLIClient
    private let brewClient: BrewClient
    private let nodeClient: NodeClient
    private let dockerClient: DockerClient
    private let awsCLIClient: AWSCLIClient

    // MARK: - Init

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
        self.brewClient = BrewClient(cliClient: cliClient)
        self.nodeClient = NodeClient(cliClient: cliClient)
        self.dockerClient = DockerClient(cliClient: cliClient)
        self.awsCLIClient = AWSCLIClient(cliClient: cliClient)
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
        let installed = await brewClient.isInstalled()
        homebrewStatus = installed ? .installed : .notInstalled
    }

    /// Check Node.js installation status
    public func checkNodeJS() async {
        nodejsStatus = .checking
        let installed = await nodeClient.isInstalled()
        nodejsStatus = installed ? .installed : .notInstalled
    }

    /// Check Docker installation status
    public func checkDocker() async {
        dockerStatus = .checking
        let installed = await dockerClient.isInstalled()
        dockerStatus = installed ? .installed : .notInstalled
    }

    /// Check AWS CLI installation status
    public func checkAWSCLI() async {
        awsCLIStatus = .checking
        let installed = await awsCLIClient.isInstalled()
        awsCLIStatus = installed ? .installed : .notInstalled
    }

    /// Check CDK installation status
    public func checkCDK() async {
        cdkStatus = .checking
        let installed = await CDKClient.isInstalled(cliClient: cliClient)
        cdkStatus = installed ? .installed : .notInstalled
    }

    /// Check GitHub CLI installation status
    public func checkGitHubCLI() async {
        githubCLIStatus = .checking
        let installed = await GitHubCLIClient.isInstalled(cliClient: cliClient)
        githubCLIStatus = installed ? .installed : .notInstalled
    }
}

/// UI state for dependency status (app-layer concern)
public enum DependencyUIState: Equatable, Sendable {
    case unknown
    case checking
    case installed
    case notInstalled

    public var isInstalled: Bool {
        self == .installed
    }

    public var isChecking: Bool {
        self == .checking
    }
}
