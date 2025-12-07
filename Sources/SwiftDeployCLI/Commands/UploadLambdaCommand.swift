import ArgumentParser
import Foundation
import SwiftDeploy

extension AWSCommand {
    struct UploadLambdaCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "upload-lambda",
            abstract: "Build locally and upload Lambda code directly to AWS"
        )

        @Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
        var awsProfile: String?

        @Option(name: .long, help: "Use aws-vault for credential management")
        var useAwsVault: Bool?

        @Flag(name: .long, help: "Skip building and upload existing lambda.zip")
        var skipBuild: Bool = false

        mutating func run() async throws {
            let projectRoot = FileManager.default.currentDirectoryPath
            let awsConfig = try AWSAuthConfiguration.resolve(
                profileName: awsProfile,
                useAWSVault: useAwsVault
            )

            let cliService = CLIService()

            let uploadService = await MainActor.run {
                LambdaUploadService(
                    projectRoot: projectRoot,
                    awsConfig: awsConfig,
                    cliService: cliService
                )
            }

            if skipBuild {
                print("📦 Uploading existing lambda.zip to AWS...\n")
                try await uploadService.upload()
            } else {
                print("🔨 Building Lambda for linux/amd64...\n")
                try await uploadService.buildAndUpload()
            }

            print("\n🎉 Lambda upload completed successfully!")
        }
    }
}
