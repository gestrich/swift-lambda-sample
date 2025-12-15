import Foundation
import ArgumentParser
import sdk_aws
import service_deploy

extension AWSCommand {
    struct TearDownCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "tear-down",
            abstract: "Destroy the CDK deployment"
        )

        @Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
        var awsProfile: String?

        @Option(name: .long, help: "Use aws-vault for credential management")
        var useAwsVault: Bool?

        @Option(name: .long, help: "CDK directory path")
        var cdkDirectory: String = "cdk"

        @Flag(name: .long, help: "Skip confirmation prompt")
        var force: Bool = false

        mutating func run() async throws {
            let awsConfig = try AWSAuthConfiguration.resolve(
                profileName: awsProfile,
                useAWSVault: useAwsVault
            )

            print("🗑️  Starting tear down...\n")

            if !force {
                print("⚠️  This will destroy the entire CDK stack and all associated resources.")
                print("   Are you sure you want to continue? (yes/no): ", terminator: "")

                guard let response = readLine()?.lowercased(),
                      response == "yes" || response == "y" else {
                    print("Cancelled.")
                    return
                }
            }

            let projectRoot = FileManager.default.currentDirectoryPath
            let service = RemoteDeploymentService(
                projectRoot: projectRoot,
                awsConfig: awsConfig,
                cdkDirectory: cdkDirectory
            )

            // Refresh to get current state (destroy only works if deployed)
            await service.refresh()

            let currentState = await service.getCurrentState()
            guard case .deployed = currentState else {
                if case .notDeployed = currentState {
                    print("ℹ️  Stack is not deployed. Nothing to tear down.")
                    return
                }
                throw DeployError.invalidConfiguration("Cannot tear down: stack is in state \(currentState)")
            }

            await service.destroy()

            let finalState = await service.getCurrentState()
            if case .failed(let reason) = finalState {
                throw DeployError.deploymentFailed(reason: reason)
            }

            print("\n🎉 Tear down completed successfully!")
        }
    }
}
