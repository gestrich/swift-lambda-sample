import sdk_cli
import sdk_cli_brew
import sdk_cli_node
import sdk_cli_docker
import sdk_aws
import sdk_github
import service_setup

/// Workflow that checks all dependency statuses and yields progress
public struct DependencyStatusWorkflow: Sendable {
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

    public struct Progress: Sendable {
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

    /// Run the workflow checking all CLI tools
    public func run() -> AsyncThrowingStream<Progress, Error> {
        run(tools: CLITool.allCases)
    }

    /// Run the workflow checking specific CLI tools
    public func run(tools: [CLITool]) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var statuses: [CLITool: CLIToolStatus] = [:]

                for tool in tools {
                    continuation.yield(Progress(step: .checking(tool)))
                    let status = await checkTool(tool)
                    statuses[tool] = status
                    continuation.yield(Progress(step: .checking(tool), detail: .status(status)))
                }

                let snapshot = DependencySnapshot(statuses: statuses)
                continuation.yield(Progress(step: .complete, detail: .snapshot(snapshot)))
                continuation.finish()
            }
        }
    }

    /// Check the installation status of a specific tool
    /// This is internal but exposed for use by DependencyInstallWorkflow
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
