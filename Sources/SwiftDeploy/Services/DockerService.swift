import Foundation

/// Service for interacting with Docker
public actor DockerService {
    private let cliService: CLIService

    public init() {
        self.cliService = CLIService.shared
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
        var arguments = ["run"]

        // Flags
        if options.detached { arguments.append("-d") }
        if options.remove { arguments.append("--rm") }
        if options.interactive { arguments.append("-i") }
        if options.tty { arguments.append("-t") }

        // Platform
        if let platform = options.platform {
            arguments.append(contentsOf: ["--platform", platform])
        }

        // Name
        if let name = options.name {
            arguments.append(contentsOf: ["--name", name])
        }

        // Network
        if let network = options.network {
            arguments.append(contentsOf: ["--network", network])
        }

        // Ports
        for (host, container) in options.ports {
            arguments.append(contentsOf: ["-p", "\(host):\(container)"])
        }

        // Volumes
        for (host, container) in options.volumes {
            arguments.append(contentsOf: ["-v", "\(host):\(container)"])
        }

        // Environment variables
        for (key, value) in options.environment {
            arguments.append(contentsOf: ["-e", "\(key)=\(value)"])
        }

        // User
        if let user = options.user {
            arguments.append(contentsOf: ["--user", user])
        }

        // Working directory
        if let workDir = options.workingDirectory {
            arguments.append(contentsOf: ["-w", workDir])
        }

        // Image
        arguments.append(image)

        // Command
        arguments.append(contentsOf: command)

        let result = try await cliService.execute(
            command: "docker",
            arguments: arguments,
            inheritIO: options.interactive && options.tty
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "docker run",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    /// Stop a container
    public func stop(container: String) async throws {
        let result = try await cliService.execute(
            command: "docker",
            arguments: ["stop", container],
            printCommand: false
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "docker stop",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    /// Remove a container
    public func remove(container: String) async throws {
        let result = try await cliService.execute(
            command: "docker",
            arguments: ["rm", container],
            printCommand: false
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "docker rm",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    /// Check if a container exists
    public func containerExists(name: String) async throws -> Bool {
        let result = try await cliService.execute(
            command: "docker",
            arguments: [
                "ps", "-a",
                "--filter", "name=^\(name)$",
                "--format", "{{.Names}}"
            ],
            printCommand: false
        )

        guard result.isSuccess else {
            return false
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == name
    }

    /// Check if a container is running
    public func containerIsRunning(name: String) async throws -> Bool {
        let result = try await cliService.execute(
            command: "docker",
            arguments: [
                "ps",
                "--filter", "name=^\(name)$",
                "--format", "{{.Names}}"
            ],
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
        var arguments = ["build"]

        // Platform
        if let platform = options.platform {
            arguments.append(contentsOf: ["--platform", platform])
        }

        // Tag
        if let tag = options.tag {
            arguments.append(contentsOf: ["-t", tag])
        }

        // Dockerfile
        if let file = options.file {
            arguments.append(contentsOf: ["-f", file])
        }

        // Build args
        for (key, value) in options.buildArgs {
            arguments.append(contentsOf: ["--build-arg", "\(key)=\(value)"])
        }

        // Secrets
        for (id, src) in options.secrets {
            arguments.append(contentsOf: ["--secret", "id=\(id),src=\(src)"])
        }

        // Context
        arguments.append(context)

        let result = try await cliService.execute(
            command: "docker",
            arguments: arguments,
            workingDirectory: options.workingDirectory
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "docker build",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    // MARK: - Network Management

    /// Create a network
    public func createNetwork(name: String) async throws {
        let result = try await cliService.execute(
            command: "docker",
            arguments: ["network", "create", name]
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "docker network create",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    /// Check if a network exists
    public func networkExists(name: String) async throws -> Bool {
        let result = try await cliService.execute(
            command: "docker",
            arguments: ["network", "inspect", name],
            printCommand: false
        )

        return result.isSuccess
    }

    /// Connect a container to a network
    public func connectToNetwork(container: String, network: String) async throws {
        let result = try await cliService.execute(
            command: "docker",
            arguments: ["network", "connect", network, container]
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "docker network connect",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    /// Check if a container is connected to a network
    public func isConnectedToNetwork(container: String, network: String) async throws -> Bool {
        let result = try await cliService.execute(
            command: "docker",
            arguments: [
                "network", "inspect", network,
                "--format", "{{range .Containers}}{{.Name}}\n{{end}}"
            ],
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
    public func getCurrentUserId() async throws -> String {
        let result = try await cliService.execute(
            command: "id",
            arguments: ["-u"],
            printCommand: false
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "id -u",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get group ID
    public func getCurrentGroupId() async throws -> String {
        let result = try await cliService.execute(
            command: "id",
            arguments: ["-g"],
            printCommand: false
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "id -g",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
