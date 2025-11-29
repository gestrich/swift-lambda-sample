import CLIKit
import Foundation

/// Docker CLI program definition using macro-based API
@CLIProgram
public struct Docker {

    // MARK: - Daemon Commands

    /// Docker info command
    /// Example: docker info
    @CLICommand
    public struct Info {
    }

    // MARK: - Container Commands

    /// Docker run command
    /// Example: docker run -d --rm --name mycontainer --platform linux/amd64 --network mynet -p 8080:80 -v /host:/container -e KEY=value --user 1000:1000 -w /app image:tag cmd arg1 arg2
    @CLICommand
    public struct Run {
        /// Run container in detached mode
        @Flag("-d") public var detached: Bool = false

        /// Automatically remove the container when it exits
        @Flag("--rm") public var remove: Bool = false

        /// Keep STDIN open even if not attached
        @Flag("-i") public var interactive: Bool = false

        /// Allocate a pseudo-TTY
        @Flag("-t") public var tty: Bool = false

        /// Set platform (e.g., linux/amd64)
        @Option public var platform: String?

        /// Assign a name to the container
        @Option public var name: String?

        /// Connect to a network
        @Option public var network: String?

        /// Publish container port(s) to host (can be repeated)
        @Option("-p") public var publish: [String] = []

        /// Mount a volume (can be repeated)
        @Option("-v") public var volume: [String] = []

        /// Set environment variable (can be repeated)
        @Option("-e") public var env: [String] = []

        /// Username or UID
        @Option public var user: String?

        /// Working directory inside the container
        @Option("-w") public var workdir: String?

        /// Image to run
        @Positional public var image: String

        /// Command and arguments to run in container
        @Positional public var command: [String] = []
    }

    /// Docker stop command
    /// Example: docker stop mycontainer
    @CLICommand
    public struct Stop {
        /// Container name or ID
        @Positional public var container: String
    }

    /// Docker rm command
    /// Example: docker rm mycontainer
    @CLICommand
    public struct Rm {
        /// Container name or ID
        @Positional public var container: String
    }

    /// Docker ps command
    /// Example: docker ps -a --filter name=^mycontainer$ --format {{.Names}}
    @CLICommand
    public struct Ps {
        /// Show all containers (default shows just running)
        @Flag("-a") public var all: Bool = false

        /// Filter output based on conditions provided (can be repeated)
        @Option public var filter: [String] = []

        /// Format output using a Go template
        @Option public var format: String?
    }

    /// Docker logs command
    /// Example: docker logs -f mycontainer
    @CLICommand
    public struct Logs {
        /// Follow log output
        @Flag("-f") public var follow: Bool = false

        /// Show timestamps
        @Flag("-t") public var timestamps: Bool = false

        /// Number of lines to show from the end of the logs
        @Option public var tail: String?

        /// Container name or ID
        @Positional public var container: String
    }

    // MARK: - Image Commands

    /// Docker build command
    /// Example: docker build --platform linux/amd64 -t myimage:tag -f Dockerfile --build-arg KEY=value --secret id=myid,src=/path .
    @CLICommand
    public struct Build {
        /// Set platform for build (e.g., linux/amd64)
        @Option public var platform: String?

        /// Name and optionally tag the image
        @Option("-t") public var tag: String?

        /// Name of the Dockerfile
        @Option("-f") public var file: String?

        /// Set build-time variables (can be repeated)
        @Option public var buildArg: [String] = []

        /// Secret to expose to build (can be repeated)
        @Option public var secret: [String] = []

        /// Build context path
        @Positional public var context: String
    }

    // MARK: - Network Commands

    /// Docker network create command
    /// Example: docker network create mynetwork
    @CLICommand("network create")
    public struct NetworkCreate {
        /// Network name
        @Positional public var name: String
    }

    /// Docker network inspect command
    /// Example: docker network inspect mynetwork --format {{range .Containers}}{{.Name}}\n{{end}}
    @CLICommand("network inspect")
    public struct NetworkInspect {
        /// Network name
        @Positional public var name: String

        /// Format output using a Go template
        @Option public var format: String?
    }

    /// Docker network connect command
    /// Example: docker network connect mynetwork mycontainer
    @CLICommand("network connect")
    public struct NetworkConnect {
        /// Network name
        @Positional public var network: String

        /// Container name or ID
        @Positional public var container: String
    }
}

// MARK: - Output Types

/// Docker container information from ps command
public struct DockerContainer: Sendable, Equatable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

/// Docker network container information
public struct DockerNetworkContainer: Sendable, Equatable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

// MARK: - Parsers

/// Parser for docker ps --format {{.Names}} output
public struct DockerPsNamesParser: CLIOutputParser {
    public init() {}

    public func parse(_ output: String) throws -> [DockerContainer] {
        let names = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .map { DockerContainer(name: $0) }
        return names
    }
}

/// Parser for docker network inspect --format output (container names)
public struct DockerNetworkContainersParser: CLIOutputParser {
    public init() {}

    public func parse(_ output: String) throws -> [DockerNetworkContainer] {
        let names = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .map { DockerNetworkContainer(name: $0) }
        return names
    }
}
