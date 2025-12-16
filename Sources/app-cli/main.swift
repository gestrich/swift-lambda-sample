import ArgumentParser
import Foundation
import service_deploy

@main
struct FeatureDeployCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-deploy",
        abstract: "CLI tool for managing Swift Lambda deployments",
        version: "2.0.0",
        subcommands: [
            AWSCommand.self,
            LocalLinuxCommand.self,
            LocalMacCommand.self
        ]
    )
}
