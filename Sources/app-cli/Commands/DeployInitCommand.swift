import Foundation
import ArgumentParser
import service_deploy
import sdk_aws
import sdk_cli
import sdk_github

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

        private static let stackName = "SwiftLambdaSampleStack"

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

            // Safety check: prevent accidental database deletion
            try await checkDatabaseSafety(cfClient: cfClient)

            // Check and warn about existing configuration
            try await checkExistingConfiguration(cfClient: cfClient)

            // Deploy infrastructure using workflow
            let apiUrl = try await deployInfrastructure(
                cdkClient: cdkClient,
                cfClient: cfClient
            )

            // Update Lambda code via GitHub Actions
            try await updateLambdaCode(projectRoot: projectRoot, cliClient: cliClient, skipPush: skipPush)

            // Initialize database if Postgres is included
            if withPostgres {
                try await initializeDatabase(apiUrl: apiUrl, cliClient: cliClient)
            }

            // Verify deployment
            try await verifyDeployment(apiUrl: apiUrl, cliClient: cliClient)

            print("\n🎉 Deployment completed successfully!")
        }

        private func checkDatabaseSafety(cfClient: CloudFormationClient) async throws {
            do {
                let state = try await cfClient.queryState(stackName: Self.stackName)

                if case .deployed = state {
                    let resources = try await cfClient.describeStackResources(name: Self.stackName)
                    let hasExistingDatabase = resources.contains {
                        $0.logicalResourceId.contains("Database") && $0.resourceType.contains("RDS")
                    }

                    if hasExistingDatabase && !withPostgres {
                        throw DeployError.invalidConfiguration(
                            "Cannot remove database with deploy-init. Use 'tear-down' first if you want to remove the database."
                        )
                    }
                }
            } catch let error as DeployError {
                throw error
            } catch {
                // Stack doesn't exist or other error - safe to proceed
            }
        }

        private func checkExistingConfiguration(cfClient: CloudFormationClient) async throws {
            do {
                let state = try await cfClient.queryState(stackName: Self.stackName)

                if case .deployed = state {
                    let resources = try await cfClient.describeStackResources(name: Self.stackName)

                    print("\n⚠️  WARNING: Stack already exists!")
                    print("   Current configuration:")
                    print("     Database: \(resources.hasDatabase ? "YES" : "NO")")
                    print("     NAT Gateway: \(resources.hasNATGateway ? "YES" : "NO")")
                    print("\n   New configuration:")
                    print("     Database: \(withPostgres ? "YES" : "NO")")
                    print("     NAT Gateway: \(withNatGateway ? "YES" : "NO")")
                    print("\n   Updating existing stack...\n")
                }
            } catch {
                // Stack doesn't exist - that's fine for deploy-init
            }
        }

        private func deployInfrastructure(
            cdkClient: CDKClient,
            cfClient: CloudFormationClient
        ) async throws -> String {
            let workflow = DeployWorkflow(
                cdkClient: cdkClient,
                cfClient: cfClient,
                stackName: Self.stackName
            )

            let options = DeployWorkflow.Options(
                withPostgres: withPostgres,
                withNATGateway: withNatGateway
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

            guard let outputs = finalOutputs, let apiUrl = outputs.apiGatewayUrl else {
                throw DeployError.deploymentFailed(reason: "Could not find ApiGatewayUrl in stack outputs")
            }

            print("\n📋 Stack Outputs:")
            for (key, value) in outputs.allOutputs.sorted(by: { $0.key < $1.key }) {
                print("  \(key): \(value)")
            }
            print("\n✅ CDK deployment completed successfully")

            return apiUrl
        }

        private func updateLambdaCode(projectRoot: String, cliClient: CLIClient, skipPush: Bool) async throws {
            guard let githubConfig = GitHubConfiguration.loadConfig() else {
                throw DeployError.configurationMissing(
                    file: "~/.swiftSampleDemo/github-config.json",
                    hint: "Create with: {\"repository\": \"owner/repo\", \"branch\": \"dev\"}"
                )
            }

            let githubClient = makeGitHubActionsClient(
                repoPath: projectRoot,
                config: githubConfig,
                cliClient: cliClient
            )
            let gitClient = GitClient(repoPath: projectRoot, cliClient: cliClient)

            print("\n📦 Updating Lambda code...")

            if !skipPush {
                let hasCommitsToPush = try await gitClient.hasCommitsToPush()

                if hasCommitsToPush {
                    print("   Pushing commits...")
                    let beforeRunId = try await githubClient.getLatestRunId()
                    try await gitClient.push()

                    print("   Waiting for GitHub Actions workflow...")
                    try await githubClient.waitForNewWorkflowCompletion(
                        afterRunId: beforeRunId,
                        timeoutMinutes: 10
                    )
                } else {
                    print("   ✅ No commits to push")
                    print("   🔄 Triggering workflow to redeploy current code...")
                    try await githubClient.triggerWorkflowAndWait(
                        workflowName: "Dev Deploy",
                        timeoutMinutes: 10
                    )
                }
            } else {
                print("   ⏭️  Skipping git push (--skip-push enabled)")
                print("   🔄 Triggering workflow...")
                try await githubClient.triggerWorkflowAndWait(
                    workflowName: "Dev Deploy",
                    timeoutMinutes: 10
                )
            }

            print("   ✅ Lambda code updated")
        }

        private func initializeDatabase(apiUrl: String, cliClient: CLIClient) async throws {
            print("\n🗄️  Initializing database...")
            print("   → POST \(apiUrl)api/database")

            let curlCommand = Curl.Request.post(url: "\(apiUrl)api/database", silent: true)
            let result = try await cliClient.executeForResult(curlCommand, printCommand: false)

            if !result.isSuccess {
                let errorOutput = result.stderr.isEmpty ? result.stdout : result.stderr
                throw DeployError.commandFailed(
                    command: "curl POST /api/database",
                    exitCode: result.exitCode,
                    output: errorOutput
                )
            }

            let response = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            print("   Response: \(response)")

            if !response.contains("Database Initialized") {
                throw DeployError.deploymentFailed(reason: "Unexpected database init response: \(response)")
            }

            print("   ✓ Database initialized successfully")
        }

        private func verifyDeployment(apiUrl: String, cliClient: CLIClient) async throws {
            print("\n🧪 Verifying deployment...")
            print("   Testing health endpoint...")
            print("   → GET \(apiUrl)api/health")

            let healthCommand = Curl.Request.get(url: "\(apiUrl)api/health", silent: true)
            let testResult = try await cliClient.executeForResult(healthCommand, printCommand: false)

            if !testResult.isSuccess {
                let errorOutput = testResult.stderr.isEmpty ? testResult.stdout : testResult.stderr
                throw DeployError.testFailed(message: "Health check failed: \(errorOutput)")
            }

            let healthResponse = testResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            print("   Response: \(healthResponse)")

            if healthResponse.contains("error") || healthResponse.contains("Error") {
                throw DeployError.testFailed(message: "Health check returned error: \(healthResponse)")
            }

            print("   ✅ Health check passed")
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
