import Foundation
import ArgumentParser
import sdk_aws
import service_deploy

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
            let awsConfig = try AWSAuthConfiguration.resolve(
                profileName: awsProfile,
                useAWSVault: useAwsVault
            )

            if awsProfile == nil {
                print("ℹ️  Using AWS profile '\(awsConfig.profileName)' from config file\n")
            }

            print("\n📦 Starting CDK deployment...")

            let projectRoot = FileManager.default.currentDirectoryPath
            let service = RemoteDeploymentService(
                projectRoot: projectRoot,
                awsConfig: awsConfig,
                cdkDirectory: cdkDirectory
            )

            // Refresh to get current state
            await service.refresh()
            let currentState = await service.getCurrentState()

            // Show detected configuration
            if case .deployed(let config, _) = currentState {
                print("\n📊 Detected existing stack configuration:")
                print("   Database: \(config.hasDatabase ? "YES" : "NO")")
                print("   NAT Gateway: \(config.hasNATGateway ? "YES" : "NO")")
                print("   → Maintaining current configuration\n")
            } else if case .notDeployed = currentState {
                print("\n⚠️  No existing stack detected")
                print("   → Using minimal configuration (no database, no NAT)")
                print("   → Use 'deploy-init' to set initial configuration\n")
            }

            // Update infrastructure maintaining current config
            await service.updateInfrastructure()

            let finalState = await service.getCurrentState()
            if case .failed(let reason) = finalState {
                throw DeployError.deploymentFailed(reason: reason)
            }

            // Display outputs
            if case .deployed(_, let outputs) = finalState {
                print("\n📋 Stack Outputs:")
                let rawOutputs = (try? await service.getRawStackOutputs()) ?? [:]
                for (key, value) in rawOutputs.sorted(by: { $0.key < $1.key }) {
                    print("  \(key): \(value)")
                }
                if outputs.apiGatewayUrl != nil {
                    print("\n✅ CDK deployment completed successfully")
                }
            }

            print("\n✅ Infrastructure deployment completed successfully!")
            print("\nℹ️  Lambda code was NOT updated. Use 'aws update-lambda' to update Lambda code.")
        }
    }
}
