import Foundation
import ArgumentParser
import service_deploy
import sdk_aws
import sdk_cli

extension AWSCommand {
    struct TearDownCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "tear-down",
            abstract: "Destroy the CDK deployment"
        )

        @ArgumentParser.Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
        var awsProfile: String?

        @ArgumentParser.Option(name: .long, help: "Use aws-vault for credential management")
        var useAwsVault: Bool?

        @ArgumentParser.Option(name: .long, help: "CDK directory path")
        var cdkDirectory: String = "cdk"

        @ArgumentParser.Flag(name: .long, help: "Skip confirmation prompt")
        var force: Bool = false

        private static let stackName = "SwiftLambdaSampleStack"

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
            let cliClient = CLIClient()
            let credentialProvider = awsConfig.makeCredentialProvider()
            let fullCdkPath = "\(projectRoot)/\(cdkDirectory)"

            let cdkClient = CDKClient(
                cdkDirectory: fullCdkPath,
                credentialProvider: credentialProvider,
                cliClient: cliClient
            )
            let cfClient = CloudFormationClient(
                credentialProvider: credentialProvider,
                cliClient: cliClient
            )

            // Check if stack exists before attempting destroy
            let currentState = try await cfClient.queryState(stackName: Self.stackName)

            switch currentState {
            case .notDeployed:
                print("ℹ️  Stack is not deployed. Nothing to tear down.")
                return

            case .deployed:
                break

            case .destroying:
                print("⚠️  Stack is already being destroyed. Monitoring progress...")

            case .deploying:
                throw DeployError.invalidConfiguration("Cannot tear down: deployment is in progress")

            case .failed(let reason):
                print("⚠️  Stack is in failed state: \(reason)")
                print("   Attempting to destroy anyway...")

            case .loading, .unknown:
                throw DeployError.invalidConfiguration("Cannot tear down: stack is in state \(currentState)")

            case .credentialExpired(let message):
                throw DeployError.invalidConfiguration("Cannot tear down: \(message)")
            }

            let workflow = DestroyWorkflow(
                cdkClient: cdkClient,
                cfClient: cfClient,
                stackName: Self.stackName
            )

            let options = DestroyWorkflow.Options(force: true)

            for try await progress in workflow.run(options: options) {
                switch progress.step {
                case .destroying:
                    if let detail = progress.detail {
                        printDestroyProgress(detail)
                    } else {
                        print("🗑️  Destroying resources...")
                    }

                case .complete:
                    break
                }
            }

            print("\n🎉 Tear down completed successfully!")
        }

        private func printDestroyProgress(_ progress: DeploymentProgress) {
            let completed = progress.completedCount
            let total = progress.resources.count
            if total > 0 {
                print("🗑️  Destroying resources: \(completed)/\(total)")
            }
        }
    }
}
