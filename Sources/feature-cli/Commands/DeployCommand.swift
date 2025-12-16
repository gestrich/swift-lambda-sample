import Foundation
import ArgumentParser
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

            try await runDeployment(projectRoot: projectRoot, awsConfig: awsConfig, cdkDirectory: cdkDirectory)
        }

        @MainActor
        private func runDeployment(projectRoot: String, awsConfig: AWSAuthConfiguration, cdkDirectory: String) async throws {
            let service = DeploymentService(
                projectRoot: projectRoot,
                awsConfig: awsConfig,
                cdkDirectory: cdkDirectory
            )

            await service.refresh()
            let currentState = service.deploymentState

            if case .deployed = currentState, let config = service.infrastructureConfiguration {
                print("\n📊 Detected existing stack configuration:")
                print("   Database: \(config.hasDatabase ? "YES" : "NO")")
                print("   NAT Gateway: \(config.hasNATGateway ? "YES" : "NO")")
                print("   → Maintaining current configuration\n")
            } else if case .notDeployed = currentState {
                print("\n⚠️  No existing stack detected")
                print("   → Using minimal configuration (no database, no NAT)")
                print("   → Use 'deploy-init' to set initial configuration\n")
            }

            await service.updateInfrastructure()

            let finalState = service.deploymentState
            if case .failed(let reason) = finalState {
                throw DeployError.deploymentFailed(reason: reason)
            }

            if case .deployed = finalState, let outputs = service.stackOutputs {
                print("\n📋 Stack Outputs:")
                for (key, value) in outputs.allOutputs.sorted(by: { $0.key < $1.key }) {
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
