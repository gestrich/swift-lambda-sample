import Foundation
import ArgumentParser
import sdk_aws
import service_deploy

extension AWSCommand {
    struct UpdateLambdaCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update-lambda",
            abstract: "Update Lambda code only (via GitHub Actions)"
        )

        @Flag(name: .long, help: "Skip git push (manually trigger workflow instead)")
        var skipPush: Bool = false

        mutating func run() async throws {
            print("🚀 Updating Lambda code...\n")

            let projectRoot = FileManager.default.currentDirectoryPath
            let awsConfig = try AWSAuthConfiguration.resolve(
                profileName: nil,
                useAWSVault: nil
            )

            let deploymentService = RemoteDeploymentService(
                projectRoot: projectRoot,
                awsConfig: awsConfig
            )

            try await deploymentService.updateLambdaCode(skipPush: skipPush)

            print("\n🎉 Lambda deployment completed successfully!")
        }
    }
}
