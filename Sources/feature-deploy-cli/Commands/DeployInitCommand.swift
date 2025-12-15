import Foundation
import ArgumentParser
import SwiftDeploy

extension AWSCommand {
    struct DeployInitCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "deploy-init",
            abstract: "Initial deployment - set infrastructure configuration"
        )

        @Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
        var awsProfile: String?

        @Option(name: .long, help: "Use aws-vault for credential management")
        var useAwsVault: Bool?

        @Option(name: .long, help: "CDK directory path")
        var cdkDirectory: String = "cdk"

        @Flag(name: .long, help: "Include PostgreSQL database (adds cost)")
        var withPostgres: Bool = false

        @Flag(name: .long, help: "Include NAT Gateway (adds cost)")
        var withNatGateway: Bool = false

        @Flag(name: .long, help: "Skip git push")
        var skipPush: Bool = false

        mutating func run() async throws {
            let awsConfig = try AWSAuthConfiguration.resolve(
                profileName: awsProfile,
                useAWSVault: useAwsVault
            )

            if awsProfile == nil {
                print("ℹ️  Using AWS profile '\(awsConfig.profileName)' from config file\n")
            }

            print("🚀 Starting deployment...\n")

            if !withPostgres && !withNatGateway {
                print("💰 MINIMAL COST MODE (default)")
                print("   - No PostgreSQL database")
                print("   - No NAT Gateway")
                print("   - Cost: ~$0/month (only pay for Lambda invocations, S3, SQS usage)")
                print("")
            }

            let projectRoot = FileManager.default.currentDirectoryPath
            let deploymentService = RemoteDeploymentService(
                projectRoot: projectRoot,
                awsConfig: awsConfig,
                cdkDirectory: cdkDirectory
            )

            let options = DeploymentConfiguration(
                skipPostgres: !withPostgres,
                skipNATGateway: !withNatGateway,
                awsProfile: awsConfig.profileName,
                cdkDirectory: cdkDirectory
            )

            try await deploymentService.deployInit(
                options: options,
                withPostgres: withPostgres,
                skipPush: skipPush
            )
        }
    }
}
