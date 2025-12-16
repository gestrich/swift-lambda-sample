import ArgumentParser
import Foundation
import service_deploy
import sdk_aws
import sdk_cli
import sdk_github

extension AWSCommand {
    struct StatusCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Check deployment and git status"
        )

        @ArgumentParser.Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
        var awsProfile: String?

        @ArgumentParser.Option(name: .long, help: "Use aws-vault for credential management")
        var useAwsVault: Bool?

        mutating func run() async throws {
            let awsConfig = try AWSAuthConfiguration.resolve(
                profileName: awsProfile,
                useAWSVault: useAwsVault
            )

            print("📊 Checking status...\n")

            let projectRoot = FileManager.default.currentDirectoryPath
            let cliClient = CLIClient(defaultWorkingDirectory: projectRoot)
            let credentialProvider = awsConfig.makeCredentialProvider()

            let cfClient = CloudFormationClient(
                credentialProvider: credentialProvider,
                cliClient: cliClient
            )
            let gitClient = GitClient(repoPath: projectRoot, cliClient: cliClient)
            let githubConfig = GitHubConfiguration.loadConfig()?.toSDKConfiguration()
            let githubClient = githubConfig.map {
                GitHubActionsClient(repoPath: projectRoot, config: $0, cliClient: cliClient)
            }

            // Git status
            let hasUncommitted = try await gitClient.hasUncommittedChanges()
            let hasCommitsToPush = try await gitClient.hasCommitsToPush()
            let currentBranch = try await gitClient.getCurrentBranch()

            print("📝 Git Status:")
            print("  Uncommitted changes: \(hasUncommitted ? "YES" : "NO")")
            print("  Commits to push: \(hasCommitsToPush ? "YES" : "NO")")
            print("  Current branch: \(currentBranch)")

            // GitHub Actions status
            if let githubClient = githubClient {
                do {
                    let (status, conclusion) = try await githubClient.getLatestRunStatus()
                    print("\n🔄 GitHub Actions:")
                    print("  Repository: \(githubClient.repository)")
                    print("  Branch: \(githubClient.branch)")
                    print("  Latest workflow status: \(status)")
                    if let conclusion = conclusion {
                        print("  Conclusion: \(conclusion)")
                    }
                } catch {
                    print("\n🔄 GitHub Actions: Unable to fetch status")
                }
            } else {
                print("\n🔄 GitHub Actions: Not configured")
                print("  Create \(GitHubConfiguration.configPath) with:")
                print("  {\"repository\": \"owner/repo\", \"branch\": \"dev\"}")
            }

            // CDK Stack status
            let stackName = CDKStackConfiguration.defaultStackName
            do {
                let state = try await cfClient.queryState(stackName: stackName)
                print("\n☁️  CDK Stack:")

                if case .deployed(let outputs) = state {
                    if outputs.isEmpty {
                        print("  Stack deployed but no outputs")
                    } else {
                        for (key, value) in outputs.sorted(by: { $0.key < $1.key }) {
                            print("  \(key): \(value)")
                        }
                    }
                } else if case .notDeployed = state {
                    print("  Stack not deployed")
                } else if case .credentialExpired(let message) = state {
                    print("  ⚠️  Credentials expired: \(message)")
                } else if case .failed(let reason) = state {
                    print("  ❌ Stack in failed state: \(reason)")
                } else if case .deploying = state {
                    print("  🔄 Deployment in progress...")
                } else if case .destroying = state {
                    print("  🔄 Destroy in progress...")
                } else {
                    print("  State: \(state)")
                }
            } catch {
                print("\n☁️  CDK Stack:")
                print("  Unable to fetch stack status: \(error.localizedDescription)")
            }
        }
    }
}
