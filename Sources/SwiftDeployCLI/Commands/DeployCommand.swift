import Foundation
import ArgumentParser
import SwiftDeploy

extension AWSCommand {
    struct DeployCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "deploy",
            abstract: "Deploy/update CDK infrastructure only (does not update Lambda code)"
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

    mutating func run() async throws {
        // Resolve AWS configuration from CLI args and config file
        let awsConfig = try AWSAuthConfiguration.resolve(
            profileName: awsProfile,
            useAWSVault: useAwsVault
        )

        if awsProfile == nil {
            print("ℹ️  Using AWS profile '\(awsConfig.profileName)' from config file\n")
        }

        print("🚀 Deploying CDK infrastructure...\n")

        if !withPostgres && !withNatGateway {
            print("💰 MINIMAL COST MODE (default)")
            print("   - No PostgreSQL database")
            print("   - No NAT Gateway")
            print("   - Cost: ~$0/month (only pay for Lambda invocations, S3, SQS usage)")
            print("")
        }

        let projectRoot = FileManager.default.currentDirectoryPath
        let deploymentService = DeploymentService(
            projectRoot: projectRoot,
            awsConfig: awsConfig
        )

        let options = DeploymentOptions(
            skipPostgres: !withPostgres,
            skipNATGateway: !withNatGateway,
            awsProfile: awsConfig.profileName,
            cdkDirectory: cdkDirectory
        )

        _ = try await deploymentService.deployInfrastructure(options: options)

        print("\n✅ Infrastructure deployment completed successfully!")
        print("\nℹ️  Lambda code was NOT updated. Use 'aws update-lambda' to update Lambda code.")
    }
    }
}
