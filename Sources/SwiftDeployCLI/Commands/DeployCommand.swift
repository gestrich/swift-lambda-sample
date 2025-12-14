import Foundation
import ArgumentParser
import SwiftDeploy

extension AWSCommand {
    struct DeployCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "deploy",
            abstract: "Deploy/update CDK infrastructure (maintains current configuration)"
        )

    @Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
    var awsProfile: String?

    @Option(name: .long, help: "Use aws-vault for credential management")
    var useAwsVault: Bool?

    @Option(name: .long, help: "CDK directory path")
    var cdkDirectory: String = "cdk"

    mutating func run() async throws {
        // Resolve AWS configuration from CLI args and config file
        let awsConfig = try AWSAuthConfiguration.resolve(
            profileName: awsProfile,
            useAWSVault: useAwsVault
        )

        if awsProfile == nil {
            print("ℹ️  Using AWS profile '\(awsConfig.profileName)' from config file\n")
        }

        let projectRoot = FileManager.default.currentDirectoryPath
        let remoteService = await MainActor.run {
            RemoteServiceModel(
                projectRoot: projectRoot,
                awsConfig: awsConfig
            )
        }

        // Options with minimal config - actual config will be detected from AWS
        let options = DeploymentOptions(
            skipPostgres: true,
            skipNATGateway: true,
            awsProfile: awsConfig.profileName,
            cdkDirectory: cdkDirectory
        )

        _ = try await remoteService.deployInfrastructure(options: options)

        print("\n✅ Infrastructure deployment completed successfully!")
        print("\nℹ️  Lambda code was NOT updated. Use 'aws update-lambda' to update Lambda code.")
    }
    }
}
