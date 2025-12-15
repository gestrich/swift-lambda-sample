import CLIKit
@testable import service_deploy
import Testing

@Suite("Docker CLI Command Tests")
struct DockerCLITests {

    @Test("Docker program name")
    func testProgramName() {
        #expect(Docker.programName == "docker")
    }
}

// MARK: - Daemon Commands

@Suite("Docker Info Tests")
struct DockerInfoTests {

    @Test("Info command path")
    func testCommandPath() {
        #expect(Docker.Info.commandPath == ["info"])
    }

    @Test("Info command line")
    func testCommandLine() {
        let cmd = Docker.Info()
        #expect(cmd.commandLine == ["docker", "info"])
    }

    @Test("Info command string")
    func testCommandString() {
        let cmd = Docker.Info()
        #expect(cmd.commandString == "docker info")
    }
}

// MARK: - Container Commands

@Suite("Docker Run Tests")
struct DockerRunTests {

    @Test("Run command path")
    func testCommandPath() {
        #expect(Docker.Run.commandPath == ["run"])
    }

    @Test("Run minimal command line")
    func testMinimalCommandLine() {
        let cmd = Docker.Run(image: "nginx:latest")
        #expect(cmd.commandLine == ["docker", "run", "nginx:latest"])
    }

    @Test("Run with detached flag")
    func testWithDetached() {
        let cmd = Docker.Run(detached: true, image: "nginx:latest")
        #expect(cmd.commandLine == ["docker", "run", "-d", "nginx:latest"])
    }

    @Test("Run with remove flag")
    func testWithRemove() {
        let cmd = Docker.Run(remove: true, image: "nginx:latest")
        #expect(cmd.commandLine == ["docker", "run", "--rm", "nginx:latest"])
    }

    @Test("Run with interactive flag")
    func testWithInteractive() {
        let cmd = Docker.Run(interactive: true, image: "ubuntu:22.04")
        #expect(cmd.commandLine == ["docker", "run", "-i", "ubuntu:22.04"])
    }

    @Test("Run with tty flag")
    func testWithTty() {
        let cmd = Docker.Run(tty: true, image: "ubuntu:22.04")
        #expect(cmd.commandLine == ["docker", "run", "-t", "ubuntu:22.04"])
    }

    @Test("Run with platform option")
    func testWithPlatform() {
        let cmd = Docker.Run(platform: "linux/amd64", image: "nginx:latest")
        #expect(cmd.commandLine == ["docker", "run", "--platform", "linux/amd64", "nginx:latest"])
    }

    @Test("Run with name option")
    func testWithName() {
        let cmd = Docker.Run(name: "mycontainer", image: "nginx:latest")
        #expect(cmd.commandLine == ["docker", "run", "--name", "mycontainer", "nginx:latest"])
    }

    @Test("Run with network option")
    func testWithNetwork() {
        let cmd = Docker.Run(network: "mynetwork", image: "nginx:latest")
        #expect(cmd.commandLine == ["docker", "run", "--network", "mynetwork", "nginx:latest"])
    }

    @Test("Run with single port")
    func testWithSinglePort() {
        let cmd = Docker.Run(publish: ["8080:80"], image: "nginx:latest")
        #expect(cmd.commandLine == ["docker", "run", "-p", "8080:80", "nginx:latest"])
    }

    @Test("Run with multiple ports")
    func testWithMultiplePorts() {
        let cmd = Docker.Run(publish: ["8080:80", "443:443"], image: "nginx:latest")
        #expect(cmd.commandLine == ["docker", "run", "-p", "8080:80", "-p", "443:443", "nginx:latest"])
    }

    @Test("Run with single volume")
    func testWithSingleVolume() {
        let cmd = Docker.Run(volume: ["/host:/container"], image: "nginx:latest")
        #expect(cmd.commandLine == ["docker", "run", "-v", "/host:/container", "nginx:latest"])
    }

    @Test("Run with multiple volumes")
    func testWithMultipleVolumes() {
        let cmd = Docker.Run(volume: ["/data:/data", "/config:/config"], image: "nginx:latest")
        #expect(cmd.commandLine == ["docker", "run", "-v", "/data:/data", "-v", "/config:/config", "nginx:latest"])
    }

    @Test("Run with single environment variable")
    func testWithSingleEnvVar() {
        let cmd = Docker.Run(env: ["KEY=value"], image: "nginx:latest")
        #expect(cmd.commandLine == ["docker", "run", "-e", "KEY=value", "nginx:latest"])
    }

    @Test("Run with multiple environment variables")
    func testWithMultipleEnvVars() {
        let cmd = Docker.Run(env: ["KEY1=value1", "KEY2=value2"], image: "nginx:latest")
        #expect(cmd.commandLine == ["docker", "run", "-e", "KEY1=value1", "-e", "KEY2=value2", "nginx:latest"])
    }

    @Test("Run with user option")
    func testWithUser() {
        let cmd = Docker.Run(user: "1000:1000", image: "nginx:latest")
        #expect(cmd.commandLine == ["docker", "run", "--user", "1000:1000", "nginx:latest"])
    }

    @Test("Run with workdir option")
    func testWithWorkdir() {
        let cmd = Docker.Run(workdir: "/app", image: "nginx:latest")
        #expect(cmd.commandLine == ["docker", "run", "-w", "/app", "nginx:latest"])
    }

    @Test("Run with command arguments")
    func testWithCommand() {
        let cmd = Docker.Run(image: "ubuntu:22.04", command: ["echo", "hello"])
        #expect(cmd.commandLine == ["docker", "run", "ubuntu:22.04", "echo", "hello"])
    }

    @Test("Run with all options")
    func testWithAllOptions() {
        let cmd = Docker.Run(
            detached: true,
            remove: true,
            interactive: false,
            tty: false,
            platform: "linux/amd64",
            name: "mycontainer",
            network: "mynetwork",
            publish: ["8080:80"],
            volume: ["/data:/data"],
            env: ["KEY=value"],
            user: "1000:1000",
            workdir: "/app",
            image: "nginx:latest",
            command: ["nginx", "-g", "daemon off;"]
        )
        #expect(cmd.commandLine == [
            "docker", "run",
            "-d", "--rm",
            "--platform", "linux/amd64",
            "--name", "mycontainer",
            "--network", "mynetwork",
            "-p", "8080:80",
            "-v", "/data:/data",
            "-e", "KEY=value",
            "--user", "1000:1000",
            "-w", "/app",
            "nginx:latest",
            "nginx", "-g", "daemon off;"
        ])
    }

    @Test("Run command string")
    func testCommandString() {
        let cmd = Docker.Run(detached: true, name: "web", image: "nginx:latest")
        #expect(cmd.commandString == "docker run -d --name web nginx:latest")
    }
}

@Suite("Docker Stop Tests")
struct DockerStopTests {

    @Test("Stop command path")
    func testCommandPath() {
        #expect(Docker.Stop.commandPath == ["stop"])
    }

    @Test("Stop command line")
    func testCommandLine() {
        let cmd = Docker.Stop(container: "mycontainer")
        #expect(cmd.commandLine == ["docker", "stop", "mycontainer"])
    }

    @Test("Stop command string")
    func testCommandString() {
        let cmd = Docker.Stop(container: "mycontainer")
        #expect(cmd.commandString == "docker stop mycontainer")
    }
}

@Suite("Docker Rm Tests")
struct DockerRmTests {

    @Test("Rm command path")
    func testCommandPath() {
        #expect(Docker.Rm.commandPath == ["rm"])
    }

    @Test("Rm command line")
    func testCommandLine() {
        let cmd = Docker.Rm(container: "mycontainer")
        #expect(cmd.commandLine == ["docker", "rm", "mycontainer"])
    }

    @Test("Rm command string")
    func testCommandString() {
        let cmd = Docker.Rm(container: "mycontainer")
        #expect(cmd.commandString == "docker rm mycontainer")
    }
}

@Suite("Docker Ps Tests")
struct DockerPsTests {

    @Test("Ps command path")
    func testCommandPath() {
        #expect(Docker.Ps.commandPath == ["ps"])
    }

    @Test("Ps minimal command line")
    func testMinimalCommandLine() {
        let cmd = Docker.Ps()
        #expect(cmd.commandLine == ["docker", "ps"])
    }

    @Test("Ps with all flag")
    func testWithAllFlag() {
        let cmd = Docker.Ps(all: true)
        #expect(cmd.commandLine == ["docker", "ps", "-a"])
    }

    @Test("Ps with single filter")
    func testWithSingleFilter() {
        let cmd = Docker.Ps(filter: ["name=^mycontainer$"])
        #expect(cmd.commandLine == ["docker", "ps", "--filter", "name=^mycontainer$"])
    }

    @Test("Ps with multiple filters")
    func testWithMultipleFilters() {
        let cmd = Docker.Ps(filter: ["name=^web", "status=running"])
        #expect(cmd.commandLine == ["docker", "ps", "--filter", "name=^web", "--filter", "status=running"])
    }

    @Test("Ps with format option")
    func testWithFormat() {
        let cmd = Docker.Ps(format: "{{.Names}}")
        #expect(cmd.commandLine == ["docker", "ps", "--format", "{{.Names}}"])
    }

    @Test("Ps with all options")
    func testWithAllOptions() {
        let cmd = Docker.Ps(all: true, filter: ["name=^mycontainer$"], format: "{{.Names}}")
        #expect(cmd.commandLine == ["docker", "ps", "-a", "--filter", "name=^mycontainer$", "--format", "{{.Names}}"])
    }

    @Test("Ps command string")
    func testCommandString() {
        let cmd = Docker.Ps(all: true, format: "{{.Names}}")
        #expect(cmd.commandString == "docker ps -a --format {{.Names}}")
    }
}

@Suite("Docker Logs Tests")
struct DockerLogsTests {

    @Test("Logs command path")
    func testCommandPath() {
        #expect(Docker.Logs.commandPath == ["logs"])
    }

    @Test("Logs minimal command line")
    func testMinimalCommandLine() {
        let cmd = Docker.Logs(container: "mycontainer")
        #expect(cmd.commandLine == ["docker", "logs", "mycontainer"])
    }

    @Test("Logs with follow flag")
    func testWithFollowFlag() {
        let cmd = Docker.Logs(follow: true, container: "mycontainer")
        #expect(cmd.commandLine == ["docker", "logs", "-f", "mycontainer"])
    }

    @Test("Logs with timestamps flag")
    func testWithTimestampsFlag() {
        let cmd = Docker.Logs(timestamps: true, container: "mycontainer")
        #expect(cmd.commandLine == ["docker", "logs", "-t", "mycontainer"])
    }

    @Test("Logs with tail option")
    func testWithTailOption() {
        let cmd = Docker.Logs(tail: "100", container: "mycontainer")
        #expect(cmd.commandLine == ["docker", "logs", "--tail", "100", "mycontainer"])
    }

    @Test("Logs with all options")
    func testWithAllOptions() {
        let cmd = Docker.Logs(follow: true, timestamps: true, tail: "50", container: "mycontainer")
        #expect(cmd.commandLine == ["docker", "logs", "-f", "-t", "--tail", "50", "mycontainer"])
    }

    @Test("Logs command string")
    func testCommandString() {
        let cmd = Docker.Logs(follow: true, container: "mycontainer")
        #expect(cmd.commandString == "docker logs -f mycontainer")
    }
}

// MARK: - Image Commands

@Suite("Docker Build Tests")
struct DockerBuildTests {

    @Test("Build command path")
    func testCommandPath() {
        #expect(Docker.Build.commandPath == ["build"])
    }

    @Test("Build minimal command line")
    func testMinimalCommandLine() {
        let cmd = Docker.Build(context: ".")
        #expect(cmd.commandLine == ["docker", "build", "."])
    }

    @Test("Build with platform option")
    func testWithPlatform() {
        let cmd = Docker.Build(platform: "linux/amd64", context: ".")
        #expect(cmd.commandLine == ["docker", "build", "--platform", "linux/amd64", "."])
    }

    @Test("Build with tag option")
    func testWithTag() {
        let cmd = Docker.Build(tag: "myimage:latest", context: ".")
        #expect(cmd.commandLine == ["docker", "build", "-t", "myimage:latest", "."])
    }

    @Test("Build with file option")
    func testWithFile() {
        let cmd = Docker.Build(file: "Dockerfile.prod", context: ".")
        #expect(cmd.commandLine == ["docker", "build", "-f", "Dockerfile.prod", "."])
    }

    @Test("Build with single build arg")
    func testWithSingleBuildArg() {
        let cmd = Docker.Build(buildArg: ["VERSION=1.0.0"], context: ".")
        #expect(cmd.commandLine == ["docker", "build", "--build-arg", "VERSION=1.0.0", "."])
    }

    @Test("Build with multiple build args")
    func testWithMultipleBuildArgs() {
        let cmd = Docker.Build(buildArg: ["VERSION=1.0.0", "ENV=prod"], context: ".")
        #expect(cmd.commandLine == ["docker", "build", "--build-arg", "VERSION=1.0.0", "--build-arg", "ENV=prod", "."])
    }

    @Test("Build with single secret")
    func testWithSingleSecret() {
        let cmd = Docker.Build(secret: ["id=mysecret,src=/path/to/secret"], context: ".")
        #expect(cmd.commandLine == ["docker", "build", "--secret", "id=mysecret,src=/path/to/secret", "."])
    }

    @Test("Build with multiple secrets")
    func testWithMultipleSecrets() {
        let cmd = Docker.Build(secret: ["id=secret1,src=/path1", "id=secret2,src=/path2"], context: ".")
        #expect(cmd.commandLine == ["docker", "build", "--secret", "id=secret1,src=/path1", "--secret", "id=secret2,src=/path2", "."])
    }

    @Test("Build with all options")
    func testWithAllOptions() {
        let cmd = Docker.Build(
            platform: "linux/amd64",
            tag: "myimage:latest",
            file: "Dockerfile",
            buildArg: ["VERSION=1.0.0"],
            secret: ["id=gh,src=/path"],
            context: "."
        )
        #expect(cmd.commandLine == [
            "docker", "build",
            "--platform", "linux/amd64",
            "-t", "myimage:latest",
            "-f", "Dockerfile",
            "--build-arg", "VERSION=1.0.0",
            "--secret", "id=gh,src=/path",
            "."
        ])
    }

    @Test("Build command string")
    func testCommandString() {
        let cmd = Docker.Build(tag: "myimage:latest", context: ".")
        #expect(cmd.commandString == "docker build -t myimage:latest .")
    }
}

// MARK: - Network Commands

@Suite("Docker Network Create Tests")
struct DockerNetworkCreateTests {

    @Test("Network.Create command path")
    func testCommandPath() {
        #expect(Docker.Network.Create.commandPath == ["network", "create"])
    }

    @Test("Network.Create command line")
    func testCommandLine() {
        let cmd = Docker.Network.Create(name: "mynetwork")
        #expect(cmd.commandLine == ["docker", "network", "create", "mynetwork"])
    }

    @Test("Network.Create command string")
    func testCommandString() {
        let cmd = Docker.Network.Create(name: "mynetwork")
        #expect(cmd.commandString == "docker network create mynetwork")
    }
}

@Suite("Docker Network Inspect Tests")
struct DockerNetworkInspectTests {

    @Test("Network.Inspect command path")
    func testCommandPath() {
        #expect(Docker.Network.Inspect.commandPath == ["network", "inspect"])
    }

    @Test("Network.Inspect minimal command line")
    func testMinimalCommandLine() {
        let cmd = Docker.Network.Inspect(name: "mynetwork")
        #expect(cmd.commandLine == ["docker", "network", "inspect", "mynetwork"])
    }

    @Test("Network.Inspect with format")
    func testWithFormat() {
        let cmd = Docker.Network.Inspect(name: "mynetwork", format: "{{range .Containers}}{{.Name}}\n{{end}}")
        #expect(cmd.commandLine == [
            "docker", "network", "inspect",
            "mynetwork",
            "--format", "{{range .Containers}}{{.Name}}\n{{end}}"
        ])
    }

    @Test("Network.Inspect command string")
    func testCommandString() {
        let cmd = Docker.Network.Inspect(name: "mynetwork")
        #expect(cmd.commandString == "docker network inspect mynetwork")
    }
}

@Suite("Docker Network Connect Tests")
struct DockerNetworkConnectTests {

    @Test("Network.Connect command path")
    func testCommandPath() {
        #expect(Docker.Network.Connect.commandPath == ["network", "connect"])
    }

    @Test("Network.Connect command line")
    func testCommandLine() {
        let cmd = Docker.Network.Connect(network: "mynetwork", container: "mycontainer")
        #expect(cmd.commandLine == ["docker", "network", "connect", "mynetwork", "mycontainer"])
    }

    @Test("Network.Connect command string")
    func testCommandString() {
        let cmd = Docker.Network.Connect(network: "mynetwork", container: "mycontainer")
        #expect(cmd.commandString == "docker network connect mynetwork mycontainer")
    }
}

// MARK: - Parser Tests

@Suite("Docker Ps Names Parser Tests")
struct DockerPsNamesParserTests {

    @Test("Parse single container name")
    func testParseSingleContainer() throws {
        let parser = DockerPsNamesParser()
        let output = "mycontainer\n"
        let containers = try parser.parse(output)
        #expect(containers.count == 1)
        #expect(containers[0].name == "mycontainer")
    }

    @Test("Parse multiple container names")
    func testParseMultipleContainers() throws {
        let parser = DockerPsNamesParser()
        let output = "container1\ncontainer2\ncontainer3\n"
        let containers = try parser.parse(output)
        #expect(containers.count == 3)
        #expect(containers[0].name == "container1")
        #expect(containers[1].name == "container2")
        #expect(containers[2].name == "container3")
    }

    @Test("Parse empty output")
    func testParseEmptyOutput() throws {
        let parser = DockerPsNamesParser()
        let containers = try parser.parse("")
        #expect(containers.isEmpty)
    }

    @Test("Parse whitespace only output")
    func testParseWhitespaceOutput() throws {
        let parser = DockerPsNamesParser()
        let containers = try parser.parse("   \n  \n")
        #expect(containers.isEmpty)
    }
}

@Suite("Docker Network Containers Parser Tests")
struct DockerNetworkContainersParserTests {

    @Test("Parse single container name")
    func testParseSingleContainer() throws {
        let parser = DockerNetworkContainersParser()
        let output = "mycontainer\n"
        let containers = try parser.parse(output)
        #expect(containers.count == 1)
        #expect(containers[0].name == "mycontainer")
    }

    @Test("Parse multiple container names")
    func testParseMultipleContainers() throws {
        let parser = DockerNetworkContainersParser()
        let output = "web\ndb\ncache\n"
        let containers = try parser.parse(output)
        #expect(containers.count == 3)
        #expect(containers[0].name == "web")
        #expect(containers[1].name == "db")
        #expect(containers[2].name == "cache")
    }

    @Test("Parse empty output")
    func testParseEmptyOutput() throws {
        let parser = DockerNetworkContainersParser()
        let containers = try parser.parse("")
        #expect(containers.isEmpty)
    }
}
