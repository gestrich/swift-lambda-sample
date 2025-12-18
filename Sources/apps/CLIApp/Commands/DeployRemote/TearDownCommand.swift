import ArgumentParser
import AWSSDK
import DeployRemoteFeature
import DeployCoreService

extension DeployRemoteCommand {
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

        mutating func run() async throws {
            let env = try CLIAWSEnvironment.resolve(
                awsProfile: awsProfile,
                useAwsVault: useAwsVault,
                cdkDirectory: cdkDirectory
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

            let components = DestroyWorkflow.create(
                cdkDirectory: env.cdkDirectory,
                credentialProvider: env.credentialProvider,
                cliClient: env.cliClient
            )

            let currentState = try await components.cfClient.queryState(stackName: components.stackName)

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

            let options = DestroyWorkflow.Options(force: true)

            for try await state in components.workflow.stream(options: options) {
                switch state {
                case .destroying(let progress):
                    if let detail = progress.detail, !detail.destroyProgressDescription.isEmpty {
                        print("🗑️  \(detail.destroyProgressDescription)")
                    } else {
                        print("🗑️  Destroying resources...")
                    }

                case .completed:
                    break

                case .deploying, .updatingLambda:
                    break
                }
            }

            print("\n🎉 Tear down completed successfully!")
        }
    }
}
