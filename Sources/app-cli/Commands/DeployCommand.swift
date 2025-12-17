import ArgumentParser
import sdk_aws
import service_deploy_remote
import workflows_deploy_remote

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

        mutating func run() async throws {
            let env = try CLIAWSEnvironment.resolve(
                awsProfile: awsProfile,
                useAwsVault: useAwsVault,
                cdkDirectory: cdkDirectory
            )

            print("\n📦 Starting CDK deployment...")

            let components = DeployWorkflow.create(
                cdkDirectory: env.cdkDirectory,
                credentialProvider: env.credentialProvider,
                cliClient: env.cliClient
            )

            let options = try await detectCurrentConfiguration(
                cfClient: components.cfClient,
                stackName: components.stackName
            )

            var finalOutputs: CDKStackOutputs?

            for try await state in components.workflow.run(options: options) {
                switch state {
                case .deploying(let progress):
                    switch progress.step {
                    case .building:
                        print("🔨 Building CDK TypeScript...")
                    case .deploying:
                        if let detail = progress.detail, !detail.progressDescription.isEmpty {
                            print("☁️  \(detail.progressDescription)")
                        }
                    case .monitoring:
                        if let detail = progress.detail, !detail.progressDescription.isEmpty {
                            print("☁️  \(detail.progressDescription)")
                        } else {
                            print("☁️  Monitoring CloudFormation...")
                        }
                    }

                case .completed(let snapshot):
                    finalOutputs = snapshot.outputs

                case .destroying, .updatingLambda:
                    break
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

        private func detectCurrentConfiguration(cfClient: CloudFormationClient, stackName: String) async throws -> DeployWorkflow.Options {
            do {
                let state = try await cfClient.queryState(stackName: stackName)

                if case .deployed = state {
                    let resources = try await cfClient.describeStackResources(name: stackName)

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
    }
}
