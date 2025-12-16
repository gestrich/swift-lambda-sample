import Foundation
import ArgumentParser
import sdk_aws
import service_deploy

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
            try await runDeployInit(
                projectRoot: projectRoot,
                awsConfig: awsConfig,
                cdkDirectory: cdkDirectory,
                withPostgres: withPostgres,
                withNatGateway: withNatGateway,
                skipPush: skipPush
            )
        }

        @MainActor
        private func runDeployInit(
            projectRoot: String,
            awsConfig: AWSAuthConfiguration,
            cdkDirectory: String,
            withPostgres: Bool,
            withNatGateway: Bool,
            skipPush: Bool
        ) async throws {
            let service = DeploymentService(
                projectRoot: projectRoot,
                awsConfig: awsConfig,
                cdkDirectory: cdkDirectory
            )

            await service.refresh()
            let currentState = service.deploymentState

            if case .deployed = currentState, let config = service.infrastructureConfiguration {
                print("\n⚠️  WARNING: Stack already exists!")
                print("   Current configuration:")
                print("     Database: \(config.hasDatabase ? "YES" : "NO")")
                print("     NAT Gateway: \(config.hasNATGateway ? "YES" : "NO")")
                print("\n   New configuration:")
                print("     Database: \(withPostgres ? "YES" : "NO")")
                print("     NAT Gateway: \(withNatGateway ? "YES" : "NO")")
                print("\n   Updating existing stack...\n")
            }

            let options = DeploymentService.DeployOptions(
                withPostgres: withPostgres,
                withNATGateway: withNatGateway
            )

            try await service.deployInit(
                options: options,
                skipPush: skipPush
            )

            print("\n🎉 Deployment completed successfully!")
        }
    }
}
