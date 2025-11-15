import ArgumentParser
import Foundation

@main
struct SwiftDeploy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-deploy",
        abstract: "CLI tool for managing Swift Lambda deployments",
        version: "1.0.0",
        subcommands: [
            DeployCommand.self,
            DeployLambdaCommand.self,
            TearDownCommand.self,
            StatusCommand.self
        ]
    )
}
