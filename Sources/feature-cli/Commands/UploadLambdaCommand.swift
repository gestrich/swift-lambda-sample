import ArgumentParser
import Foundation
import sdk_aws
import service_deploy

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

            let buildService = await MainActor.run {
                LambdaBuildService(
                    workingDirectory: projectRoot,
                    awsConfig: awsConfig
                )
            }

            if skipBuild {
                print("📦 Uploading existing lambda.zip to AWS...\n")
                try await buildService.upload()
            } else {
                print("🔨 Building Lambda for linux/amd64...\n")
                try await buildService.buildAndUpload()
            }

            print("\n🎉 Lambda upload completed successfully!")
        }
    }
}
