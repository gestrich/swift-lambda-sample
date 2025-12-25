import AWSSDK
import BrewCLISDK
import CLISDK
import DockerCLISDK
import GitHubSDK
import NodeCLISDK
import Uniflow

/// Use case that checks all dependency statuses and yields progress
public struct DependencyStatusUseCase: StreamingUseCase {
    private let cliClient: CLIClient
    private let brewClient: BrewClient
    private let nodeClient: NodeClient
    private let dockerClient: DockerClient
    private let awsCLIClient: AWSCLIClient

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
        self.brewClient = BrewClient(cliClient: cliClient)
        self.nodeClient = NodeClient(cliClient: cliClient)
        self.dockerClient = DockerClient(cliClient: cliClient)
        self.awsCLIClient = AWSCLIClient(cliClient: cliClient)
    }

    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checking(CLITool)
            case complete
        }

        public enum Detail: Sendable {
            case status(CLIToolStatus)
            case snapshot(DependencySnapshot)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State

    /// Options for the use case
    public struct Options: Sendable {
        public let tools: [CLITool]

        public init(tools: [CLITool] = CLITool.allCases) {
            self.tools = tools
        }

        public static let all = Options(tools: CLITool.allCases)
    }

    /// Stream the use case checking CLI tools
    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var statuses: [CLITool: CLIToolStatus] = [:]

                for tool in options.tools {
                    continuation.yield(State(step: .checking(tool)))
                    let status = await checkTool(tool)
                    statuses[tool] = status
                    continuation.yield(State(step: .checking(tool), detail: .status(status)))
                }

                let snapshot = DependencySnapshot(statuses: statuses)
                continuation.yield(State(step: .complete, detail: .snapshot(snapshot)))
                continuation.finish()
            }
        }
    }

    /// Check the installation status of a specific tool
    /// This is internal but exposed for use by DependencyInstallUseCase
    func checkTool(_ tool: CLITool) async -> CLIToolStatus {
        switch tool {
        case .homebrew:
            let installed = await brewClient.isInstalled()
            let version = installed ? await brewClient.version() : nil
            return CLIToolStatus(tool: tool, isInstalled: installed, version: version)

        case .nodejs:
            let installed = await nodeClient.isInstalled()
            let version = installed ? await nodeClient.version() : nil
            return CLIToolStatus(tool: tool, isInstalled: installed, version: version)

        case .docker:
            let installed = await dockerClient.isInstalled()
            return CLIToolStatus(tool: tool, isInstalled: installed, version: nil)

        case .awsCLI:
            let installed = await awsCLIClient.isInstalled()
            let version = installed ? await awsCLIClient.version() : nil
            return CLIToolStatus(tool: tool, isInstalled: installed, version: version)

        case .cdk:
            let installed = await CDKClient.isInstalled(cliClient: cliClient)
            return CLIToolStatus(tool: tool, isInstalled: installed, version: nil)

        case .githubCLI:
            let installed = await GitHubCLIClient.isInstalled(cliClient: cliClient)
            return CLIToolStatus(tool: tool, isInstalled: installed, version: nil)
        }
    }
}
