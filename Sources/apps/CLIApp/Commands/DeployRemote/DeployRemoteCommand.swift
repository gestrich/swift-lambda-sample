import ArgumentParser
import AWSSDK
import DeployRemoteFeature
import Foundation

/// Top-level command for all AWS operations
struct DeployRemoteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aws",
        abstract: "AWS deployment and management operations",
        subcommands: [
            DeployInitCommand.self,
            DeployCommand.self,
            UpdateLambdaCommand.self,
            UploadLambdaCommand.self,
            TearDownCommand.self,
            StatusCommand.self
        ]
    )
}
