import Foundation
import ArgumentParser
import service_deploy
import sdk_aws
import sdk_cli

extension AWSCommand {
    struct DeployCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "deploy",
            abstract: "Deploy/update CDK infrastructure (maintains current configuration)"
        )

        @ArgumentParser.Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
        var awsProfile: String?

        @ArgumentParser.Option(name: .long, help: "Use aws-vault for credential management")
        var useAwsVault: Bool?

        @ArgumentParser.Option(name: .long, help: "CDK directory path")
        var cdkDirectory: String = "cdk"

        private static let stackName = "SwiftLambdaSampleStack"

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

            // Query current configuration to determine deploy options
            let options = try await detectCurrentConfiguration(cfClient: cfClient)

            let workflow = DeployWorkflow(
                cdkClient: cdkClient,
                cfClient: cfClient,
                stackName: Self.stackName
            )

            var finalOutputs: CDKStackOutputs?

            for try await progress in workflow.run(options: options) {
                switch progress.step {
                case .building:
                    print("🔨 Building CDK TypeScript...")

                case .deploying:
                    if case .cdk(let deployProgress) = progress.detail {
                        printDeployProgress(deployProgress)
                    }

                case .monitoring:
                    if case .cdk(let deployProgress) = progress.detail {
                        printDeployProgress(deployProgress)
                    } else {
                        print("☁️  Monitoring CloudFormation...")
                    }

                case .complete:
                    if case .outputs(let outputs, _) = progress.detail {
                        finalOutputs = outputs
                    }
                }
            }

            if let outputs = finalOutputs {
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

        private func detectCurrentConfiguration(cfClient: CloudFormationClient) async throws -> DeployWorkflow.Options {
            do {
                let state = try await cfClient.queryState(stackName: Self.stackName)

                if case .deployed = state {
                    let resources = try await cfClient.describeStackResources(name: Self.stackName)

                    print("\n📊 Detected existing stack configuration:")
                    print("   Database: \(resources.hasDatabase ? "YES" : "NO")")
                    print("   NAT Gateway: \(resources.hasNATGateway ? "YES" : "NO")")
                    print("   → Maintaining current configuration\n")

                    return DeployWorkflow.Options(
                        withPostgres: resources.hasDatabase,
                        withNATGateway: resources.hasNATGateway
                    )
                }
            } catch {
                // Stack doesn't exist or error - use minimal config
            }

            print("\n⚠️  No existing stack detected")
            print("   → Using minimal configuration (no database, no NAT)")
            print("   → Use 'deploy-init' to set initial configuration\n")

            return .minimal
        }

        private func printDeployProgress(_ progress: DeploymentProgress) {
            let completed = progress.completedCount
            let total = progress.resources.count
            if total > 0 {
                print("☁️  Deploying resources: \(completed)/\(total)")
            }
        }
    }
}
