import sdk_cli
import Foundation

/// Client for interacting with Docker CLI
public struct DockerClient: Sendable {
    private let cliClient: CLIClient

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
    }

    // MARK: - Installation Check

    /// Check if Docker is installed
    public func isInstalled() async -> Bool {
        do {
            let result = try await cliClient.executeForResult(Docker.Version(), printCommand: false)
            return result.isSuccess
        } catch {
            return false
        }
    }

    // MARK: - Docker Daemon

    /// Check if Docker daemon is running
    public func isDockerRunning() async -> Bool {
        do {
            let result = try await cliClient.executeForResult(Docker.Info(), printCommand: false)
            return result.isSuccess
        } catch {
            return false
        }
    }

    // MARK: - Container Management

    public struct RunOptions: Sendable {
        public var detached: Bool
        public var remove: Bool
        public var interactive: Bool
        public var tty: Bool
        public var platform: String?
        public var name: String?
        public var network: String?
        public var ports: [(host: Int, container: Int)]
        public var volumes: [(host: String, container: String)]
        public var environment: [String: String]
        public var user: String?
        public var workingDirectory: String?

        public init(
            detached: Bool = false,
            remove: Bool = false,
            interactive: Bool = false,
            tty: Bool = false,
            platform: String? = nil,
            name: String? = nil,
            network: String? = nil,
            ports: [(host: Int, container: Int)] = [],
            volumes: [(host: String, container: String)] = [],
            environment: [String: String] = [:],
            user: String? = nil,
            workingDirectory: String? = nil
        ) {
            self.detached = detached
            self.remove = remove
            self.interactive = interactive
            self.tty = tty
            self.platform = platform
            self.name = name
            self.network = network
            self.ports = ports
            self.volumes = volumes
            self.environment = environment
            self.user = user
            self.workingDirectory = workingDirectory
        }
    }

    /// Run a Docker container
    public func run(
        image: String,
        command: [String] = [],
        options: RunOptions = RunOptions(),
        output: CLIOutputStream? = nil
    ) async throws {
        let portMappings = options.ports.map { "\($0.host):\($0.container)" }
        let volumeMappings = options.volumes.map { "\($0.host):\($0.container)" }
        let envVars = options.environment.map { "\($0.key)=\($0.value)" }

        let dockerRun = Docker.Run(
            detached: options.detached,
            remove: options.remove,
            interactive: options.interactive,
            tty: options.tty,
            platform: options.platform,
            name: options.name,
            network: options.network,
            publish: portMappings,
            volume: volumeMappings,
            env: envVars,
            user: options.user,
            workdir: options.workingDirectory,
            image: image,
            command: command
        )

        let result = try await cliClient.executeForResult(
            dockerRun,
            inheritIO: options.interactive && options.tty,
            output: output
        )

        guard result.isSuccess else {
            throw DockerError.commandFailed(
                command: "docker run",
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    /// Start an existing stopped container
    public func start(container: String) async throws {
        let result = try await cliClient.executeForResult(
            Docker.Start(container: container),
            printCommand: false
        )

        guard result.isSuccess else {
            throw DockerError.commandFailed(
                command: "docker start",
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    /// Stop a container
    public func stop(container: String) async throws {
        let result = try await cliClient.executeForResult(
            Docker.Stop(container: container),
            printCommand: false
        )

        guard result.isSuccess else {
            throw DockerError.commandFailed(
                command: "docker stop",
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    /// Remove a container
    public func remove(container: String) async throws {
        let result = try await cliClient.executeForResult(
            Docker.Rm(container: container),
            printCommand: false
        )

        guard result.isSuccess else {
            throw DockerError.commandFailed(
                command: "docker rm",
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    /// Check if a container exists
    public func containerExists(name: String) async throws -> Bool {
        let result = try await cliClient.executeForResult(
            Docker.Ps(all: true, filter: ["name=^\(name)$"], format: "{{.Names}}"),
            printCommand: false
        )

        guard result.isSuccess else {
            return false
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == name
    }

    /// Check if a container is running
    public func containerIsRunning(name: String) async throws -> Bool {
        let result = try await cliClient.executeForResult(
            Docker.Ps(filter: ["name=^\(name)$"], format: "{{.Names}}"),
            printCommand: false
        )

        guard result.isSuccess else {
            return false
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == name
    }

    // MARK: - Image Management

    public struct BuildOptions: Sendable {
        public var platform: String?
        public var tag: String?
        public var file: String?
        public var buildArgs: [String: String]
        public var secrets: [(id: String, src: String)]
        public var workingDirectory: String?

        public init(
            platform: String? = nil,
            tag: String? = nil,
            file: String? = nil,
            buildArgs: [String: String] = [:],
            secrets: [(id: String, src: String)] = [],
            workingDirectory: String? = nil
        ) {
            self.platform = platform
            self.tag = tag
            self.file = file
            self.buildArgs = buildArgs
            self.secrets = secrets
            self.workingDirectory = workingDirectory
        }
    }

    /// Build a Docker image
    public func build(
        context: String = ".",
        options: BuildOptions = BuildOptions(),
        output: CLIOutputStream? = nil
    ) async throws {
        let buildArgStrings = options.buildArgs.map { "\($0.key)=\($0.value)" }
        let secretStrings = options.secrets.map { "id=\($0.id),src=\($0.src)" }

        let dockerBuild = Docker.Build(
            platform: options.platform,
            tag: options.tag,
            file: options.file,
            buildArg: buildArgStrings,
            secret: secretStrings,
            context: context
        )

        let dockerCommand = dockerBuild.commandString
        let fullCommand: String
        if let workDir = options.workingDirectory {
            fullCommand = "cd \"\(workDir)\" && \(dockerCommand)"
        } else {
            fullCommand = dockerCommand
        }

        let result = try await cliClient.executeForResult(Sh(command: fullCommand), output: output)

        guard result.isSuccess else {
            throw DockerError.commandFailed(
                command: "docker build",
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    // MARK: - Network Management

    /// Create a network
    public func createNetwork(name: String) async throws {
        let result = try await cliClient.executeForResult(
            Docker.Network.Create(name: name)
        )

        guard result.isSuccess else {
            throw DockerError.commandFailed(
                command: "docker network create",
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    /// Check if a network exists
    public func networkExists(name: String) async throws -> Bool {
        let result = try await cliClient.executeForResult(
            Docker.Network.Inspect(name: name),
            printCommand: false
        )

        return result.isSuccess
    }

    /// Connect a container to a network
    public func connectToNetwork(container: String, network: String) async throws {
        let result = try await cliClient.executeForResult(
            Docker.Network.Connect(network: network, container: container)
        )

        guard result.isSuccess else {
            throw DockerError.commandFailed(
                command: "docker network connect",
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    /// Check if a container is connected to a network
    public func isConnectedToNetwork(container: String, network: String) async throws -> Bool {
        let result = try await cliClient.executeForResult(
            Docker.Network.Inspect(name: network, format: "{{range .Containers}}{{.Name}}\n{{end}}"),
            printCommand: false
        )

        guard result.isSuccess else {
            return false
        }

        let containers = result.stdout.components(separatedBy: "\n")
        return containers.contains(container)
    }

    // MARK: - Helper Operations

    /// Get user ID
    public func getCurrentUserId() async throws -> Int {
        try await cliClient.execute(Id(userId: true), parser: IdParser(), printCommand: false)
    }

    /// Get group ID
    public func getCurrentGroupId() async throws -> Int {
        try await cliClient.execute(Id(groupId: true), parser: IdParser(), printCommand: false)
    }
}
