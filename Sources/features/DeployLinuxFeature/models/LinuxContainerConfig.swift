import Foundation

/// Configuration for Lambda container in Linux development workflow.
/// Defines container settings, networking, and port mappings.
public struct LinuxContainerConfig: Sendable {
    public let containerName: String
    public let swiftImage: String
    public let hostPort: Int
    public let containerPort: Int
    public let networkName: String
    public let workingDirectory: String

    public init(
        containerName: String,
        swiftImage: String,
        hostPort: Int,
        containerPort: Int,
        networkName: String,
        workingDirectory: String
    ) {
        self.containerName = containerName
        self.swiftImage = swiftImage
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.networkName = networkName
        self.workingDirectory = workingDirectory
    }

    /// Create the default Linux container configuration.
    /// Uses port 8081 to avoid conflict with Xcode local service (port 8080).
    public static func `default`(workingDirectory: String) -> LinuxContainerConfig {
        LinuxContainerConfig(
            containerName: "lambda-linux-container",
            swiftImage: "swift:6.2.0-amazonlinux2",
            hostPort: 8081,
            containerPort: 7000,
            networkName: "lambda-linux",
            workingDirectory: workingDirectory
        )
    }
}
