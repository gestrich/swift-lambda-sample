import ArgumentParser
import Foundation
import DeployRemoteFeature

@main
struct FeatureDeployCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-deploy",
        abstract: "CLI tool for managing Swift Lambda deployments",
        version: "2.0.0",
        subcommands: [
            DeployRemoteCommand.self,
            DeployLinuxCommand.self,
            DeployXcodeCommand.self
        ]
    )
}
