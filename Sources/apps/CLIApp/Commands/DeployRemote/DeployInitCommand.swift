import ArgumentParser
import AWSSDK
import DeployRemoteFeature

extension DeployRemoteCommand {
    struct DeployInitCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "deploy-init",
            abstract: "Initial deployment - set infrastructure configuration"
        )

        @ArgumentParser.Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
        var awsProfile: String?

        @ArgumentParser.Option(name: .long, help: "Use aws-vault for credential management")
        var useAwsVault: Bool?

        @ArgumentParser.Option(name: .long, help: "CDK directory path")
        var cdkDirectory: String = "cdk"

        @ArgumentParser.Flag(name: .long, help: "Include PostgreSQL database (adds cost)")
        var withPostgres: Bool = false

        @ArgumentParser.Flag(name: .long, help: "Include NAT Gateway (adds cost)")
        var withNatGateway: Bool = false

        @ArgumentParser.Flag(name: .long, help: "Skip git push")
        var skipPush: Bool = false

        mutating func run() async throws {
            let env = try CLIAWSEnvironment.resolve(
                awsProfile: awsProfile,
                useAwsVault: useAwsVault,
                cdkDirectory: cdkDirectory
            )

            print("🚀 Starting deployment...\n")

            if !withPostgres && !withNatGateway {
                print("💰 MINIMAL COST MODE (default)")
                print("   - No PostgreSQL database")
                print("   - No NAT Gateway")
                print("   - Cost: ~$0/month (only pay for Lambda invocations, S3, SQS usage)")
                print("")
            }

            let components = DeployInitUseCase.create(
                cdkDirectory: env.cdkDirectory,
                credentialProvider: env.credentialProvider,
                cliClient: env.cliClient,
                projectRoot: env.projectRoot
            )

            let options = DeployInitUseCase.Options(
                withPostgres: withPostgres,
                withNATGateway: withNatGateway,
                skipPush: skipPush
            )

            var finalOutputs: CDKStackOutputs?

            for try await state in components.useCase.stream(options: options) {
                printState(state, newConfig: options)

                if case .complete = state.step,
                   case .outputs(let outputs) = state.detail {
                    finalOutputs = outputs
                }
            }

            if let outputs = finalOutputs {
                print("\n📋 Stack Outputs:")
                for (key, value) in outputs.allOutputs.sorted(by: { $0.key < $1.key }) {
                    print("  \(key): \(value)")
                }
            }

            print("\n🎉 Deployment completed successfully!")
        }

        private func printState(_ state: DeployInitUseCase.State, newConfig: DeployInitUseCase.Options) {
            switch state.step {
            case .checkingSafety:
                if case .safetyCheckPassed = state.detail {
                    print("✅ Safety check passed")
                } else {
                    print("🔒 Checking safety...")
                }

            case .checkingConfiguration:
                if case .existingConfiguration(let config) = state.detail {
                    print("\n⚠️  WARNING: Stack already exists!")
                    print("   Current configuration:")
                    print("     Database: \(config.hasDatabase ? "YES" : "NO")")
                    print("     NAT Gateway: \(config.hasNATGateway ? "YES" : "NO")")
                    print("\n   New configuration:")
                    print("     Database: \(newConfig.withPostgres ? "YES" : "NO")")
                    print("     NAT Gateway: \(newConfig.withNATGateway ? "YES" : "NO")")
                    print("\n   Updating existing stack...\n")
                }

            case .deployingInfrastructure:
                if case .deployState(let deployState) = state.detail {
                    printDeployState(deployState)
                }

            case .updatingLambda:
                if case .lambdaState(let lambdaState) = state.detail {
                    printLambdaState(lambdaState)
                } else {
                    print("\n📦 Updating Lambda code...")
                }

            case .initializingDatabase:
                if case .databaseResponse(let response) = state.detail {
                    print("   Response: \(response)")
                    print("   ✓ Database initialized successfully")
                } else {
                    print("\n🗄️  Initializing database...")
                }

            case .verifyingDeployment:
                if case .healthCheckResponse(let response) = state.detail {
                    print("   Response: \(response)")
                    print("   ✅ Health check passed")
                } else {
                    print("\n🧪 Verifying deployment...")
                    print("   Testing health endpoint...")
                }

            case .complete:
                print("\n✅ CDK deployment completed successfully")
            }
        }

        private func printDeployState(_ state: UseCaseState) {
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
            case .completed:
                break
            case .destroying, .updatingLambda:
                break
            }
        }

        private func printLambdaState(_ state: UseCaseState) {
            guard case .updatingLambda(let progress) = state else { return }

            switch progress.step {
            case .checkingGitStatus:
                print("   Checking git status...")

            case .pushing:
                print("   Pushing commits...")

            case .triggeringWorkflow:
                print("   🔄 Triggering workflow...")

            case .waitingForWorkflow:
                print("   Waiting for GitHub Actions workflow...")

            case .monitoringWorkflow(let runId):
                if let detail = progress.runDetail {
                    print("   Monitoring workflow \(runId): \(detail.status)")
                } else {
                    print("   Monitoring workflow \(runId)...")
                }
            }
        }
    }
}
