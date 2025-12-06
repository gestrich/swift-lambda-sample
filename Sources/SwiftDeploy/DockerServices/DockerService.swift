import CLIKit
import Foundation

/// Service for interacting with Docker
public actor DockerService {
    private let cliService: CLIService

    public init(cliService: CLIService) {
        self.cliService = cliService
    }

    // MARK: - Docker Daemon

    /// Check if Docker daemon is running
    public func isDockerRunning() async -> Bool {
        do {
            let result = try await cliService.executeForResult(Docker.Info(), printCommand: false)
            return result.isSuccess
        } catch {
            return false
        }
    }

    /// Start Docker Desktop application
    public func startDockerDesktop() async throws {
        print("🐳 Starting Docker Desktop...")

        // Open Docker Desktop app
        let result = try await cliService.executeForResult(
            Open(application: "Docker"),
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "open -a Docker",
                exitCode: result.exitCode,
                output: "Failed to start Docker Desktop. Is it installed?"
            )
        }

        // Wait for Docker daemon to be ready
        print("   Waiting for Docker daemon to be ready...")
        let maxAttempts = 60  // Wait up to 60 seconds
        for attempt in 1...maxAttempts {
            if await isDockerRunning() {
                print("   ✅ Docker is ready")
                return
            }
            try await Task.sleep(for: .seconds(1))
            if attempt % 10 == 0 {
                print("   Still waiting... (\(attempt)s)")
            }
        }

        throw DeployError.commandFailed(
            command: "docker",
            exitCode: 1,
            output: "Docker Desktop started but daemon did not become ready within 60 seconds."
        )
    }

    /// Ensure Docker daemon is running, starting Docker Desktop if needed
    public func ensureDockerRunning() async throws {
        if await isDockerRunning() {
            return
        }

        // Try to start Docker Desktop
        try await startDockerDesktop()
    }

    // MARK: - Container Management

    public struct RunOptions {
        public var detached: Bool = false
        public var remove: Bool = false
        public var interactive: Bool = false
        public var tty: Bool = false
        public var platform: String?
        public var name: String?
        public var network: String?
        public var ports: [(host: Int, container: Int)] = []
        public var volumes: [(host: String, container: String)] = []
        public var environment: [String: String] = [:]
        public var user: String?
        public var workingDirectory: String?

        public init() {}
    }

    /// Run a Docker container
    public func run(
        image: String,
        command: [String] = [],
        options: RunOptions = RunOptions()
    ) async throws {
        // Build port mappings as strings
        let portMappings = options.ports.map { "\($0.host):\($0.container)" }

        // Build volume mappings as strings
        let volumeMappings = options.volumes.map { "\($0.host):\($0.container)" }

        // Build environment variables as KEY=value strings
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

        let result = try await cliService.executeForResult(
            dockerRun,
            inheritIO: options.interactive && options.tty
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "docker run",
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    /// Start an existing stopped container
    public func start(container: String) async throws {
        let result = try await cliService.executeForResult(
            Docker.Start(container: container),
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "docker start",
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    /// Stop a container
    public func stop(container: String) async throws {
        let result = try await cliService.executeForResult(
            Docker.Stop(container: container),
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "docker stop",
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    /// Remove a container
    public func remove(container: String) async throws {
        let result = try await cliService.executeForResult(
            Docker.Rm(container: container),
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "docker rm",
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    /// Check if a container exists
    public func containerExists(name: String) async throws -> Bool {
        let result = try await cliService.executeForResult(
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
        let result = try await cliService.executeForResult(
            Docker.Ps(filter: ["name=^\(name)$"], format: "{{.Names}}"),
            printCommand: false
        )

        guard result.isSuccess else {
            return false
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == name
    }

    // MARK: - Image Management

    public struct BuildOptions {
        public var platform: String?
        public var tag: String?
        public var file: String?
        public var buildArgs: [String: String] = [:]
        public var secrets: [(id: String, src: String)] = []
        public var workingDirectory: String?

        public init() {}
    }

    /// Build a Docker image
    public func build(
        context: String = ".",
        options: BuildOptions = BuildOptions()
    ) async throws {
        // Build buildArg as KEY=value strings
        let buildArgStrings = options.buildArgs.map { "\($0.key)=\($0.value)" }

        // Build secrets as id=X,src=Y strings
        let secretStrings = options.secrets.map { "id=\($0.id),src=\($0.src)" }

        let dockerBuild = Docker.Build(
            platform: options.platform,
            tag: options.tag,
            file: options.file,
            buildArg: buildArgStrings,
            secret: secretStrings,
            context: context
        )

        // Use shell with cd to ensure we're in the right directory
        // Docker buildkit can have issues with process.currentDirectoryURL
        let dockerCommand = dockerBuild.commandString
        let fullCommand: String
        if let workDir = options.workingDirectory {
            fullCommand = "cd \"\(workDir)\" && \(dockerCommand)"
        } else {
            fullCommand = dockerCommand
        }

        let result = try await cliService.executeForResult(Sh(command: fullCommand))

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "docker build",
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    // MARK: - Network Management

    /// Create a network
    public func createNetwork(name: String) async throws {
        let result = try await cliService.executeForResult(
            Docker.Network.Create(name: name)
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "docker network create",
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    /// Check if a network exists
    public func networkExists(name: String) async throws -> Bool {
        let result = try await cliService.executeForResult(
            Docker.Network.Inspect(name: name),
            printCommand: false
        )

        return result.isSuccess
    }

    /// Connect a container to a network
    public func connectToNetwork(container: String, network: String) async throws {
        let result = try await cliService.executeForResult(
            Docker.Network.Connect(network: network, container: container)
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "docker network connect",
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    /// Check if a container is connected to a network
    public func isConnectedToNetwork(container: String, network: String) async throws -> Bool {
        let result = try await cliService.executeForResult(
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
        try await cliService.execute(Id(userId: true), parser: IdParser(), printCommand: false)
    }

    /// Get group ID
    public func getCurrentGroupId() async throws -> Int {
        try await cliService.execute(Id(groupId: true), parser: IdParser(), printCommand: false)
    }
}
