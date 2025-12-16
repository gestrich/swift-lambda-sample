import ArgumentParser
import Foundation
import sdk_aws
import sdk_cli
import service_deploy

extension AWSCommand {
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
            let cliClient = CLIClient()
            let fullCdkPath = "\(projectRoot)/\(cdkDirectory)"

            let components = DeployInitWorkflow.create(
                cdkDirectory: fullCdkPath,
                credentialProvider: awsConfig.makeCredentialProvider(),
                cliClient: cliClient,
                projectRoot: projectRoot
            )

            let options = DeployInitWorkflow.Options(
                withPostgres: withPostgres,
                withNATGateway: withNatGateway,
                skipPush: skipPush
            )

            var finalOutputs: CDKStackOutputs?

            for try await progress in components.workflow.run(options: options) {
                printProgress(progress, newConfig: options)

                if case .complete = progress.step,
                   case .outputs(let outputs) = progress.detail {
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

        private func printProgress(_ progress: DeployInitWorkflow.Progress, newConfig: DeployInitWorkflow.Options) {
            switch progress.step {
            case .checkingSafety:
                if case .safetyCheckPassed = progress.detail {
                    print("✅ Safety check passed")
                } else {
                    print("🔒 Checking safety...")
                }

            case .checkingConfiguration:
                if case .existingConfiguration(let config) = progress.detail {
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
                if case .deployProgress(let deployProgress) = progress.detail {
                    printDeployProgress(deployProgress)
                }

            case .updatingLambda:
                if case .lambdaProgress(let lambdaProgress) = progress.detail {
                    printLambdaProgress(lambdaProgress)
                } else {
                    print("\n📦 Updating Lambda code...")
                }

            case .initializingDatabase:
                if case .databaseResponse(let response) = progress.detail {
                    print("   Response: \(response)")
                    print("   ✓ Database initialized successfully")
                } else {
                    print("\n🗄️  Initializing database...")
                }

            case .verifyingDeployment:
                if case .healthCheckResponse(let response) = progress.detail {
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

        private func printDeployProgress(_ progress: DeployWorkflow.Progress) {
            switch progress.step {
            case .building:
                print("🔨 Building CDK TypeScript...")

            case .deploying:
                if case .cdk(let deployProgress) = progress.detail {
                    printCDKProgress(deployProgress)
                }

            case .monitoring:
                if case .cdk(let deployProgress) = progress.detail {
                    printCDKProgress(deployProgress)
                } else {
                    print("☁️  Monitoring CloudFormation...")
                }

            case .complete:
                break
            }
        }

        private func printCDKProgress(_ progress: DeploymentProgress) {
            let completed = progress.completedCount
            let total = progress.resources.count
            if total > 0 {
                print("☁️  Deploying resources: \(completed)/\(total)")
            }
        }

        private func printLambdaProgress(_ progress: UpdateLambdaWorkflow.Progress) {
            switch progress.step {
            case .checkingGitStatus:
                if case .skippedPush = progress.detail {
                    print("   ⏭️  Skipping git push (--skip-push enabled)")
                }

            case .pushing:
                print("   Pushing commits...")

            case .triggeringWorkflow:
                if case .gitStatus(let hasCommits) = progress.detail, !hasCommits {
                    print("   ✅ No commits to push")
                }
                print("   🔄 Triggering workflow...")

            case .waitingForWorkflow:
                print("   Waiting for GitHub Actions workflow...")

            case .complete:
                print("   ✅ Lambda code updated")
            }
        }
    }
}
