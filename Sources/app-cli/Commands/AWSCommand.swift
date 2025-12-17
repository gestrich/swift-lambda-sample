import ArgumentParser
import Foundation
import sdk_aws
import service_deploy

/// Top-level command for all AWS operations
struct AWSCommand: AsyncParsableCommand {
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
