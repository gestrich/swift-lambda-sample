import ArgumentParser
import Foundation
import DeployRemoteFeature
import AWSSDK
import CLISDK

extension DeployRemoteCommand {
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

            let components = DeployStatusWorkflow.create(
                projectRoot: projectRoot,
                credentialProvider: credentialProvider,
                cliClient: cliClient
            )

            for try await state in components.workflow.stream() {
                printState(state)
            }
        }

        private func printState(_ state: DeployStatusWorkflow.State) {
            guard let detail = state.detail else { return }

            switch detail {
            case .gitStatus(let status):
                print("📝 Git Status:")
                print("  Uncommitted changes: \(status.hasUncommittedChanges ? "YES" : "NO")")
                print("  Commits to push: \(status.hasUnpushedCommits ? "YES" : "NO")")
                print("  Current branch: \(status.currentBranch)")

            case .githubStatus(let status):
                print("\n🔄 GitHub Actions:")
                print("  Repository: \(status.repository)")
                print("  Branch: \(status.branch)")
                print("  Latest workflow status: \(status.latestRunStatus)")
                if let conclusion = status.latestRunConclusion {
                    print("  Conclusion: \(conclusion)")
                }

            case .githubNotConfigured:
                print("\n🔄 GitHub Actions: Not configured")
                print("  Create \(GitHubConfiguration.configPath) with:")
                print("  {\"repository\": \"owner/repo\", \"branch\": \"dev\"}")

            case .githubError:
                print("\n🔄 GitHub Actions: Unable to fetch status")

            case .stackStatus(let status):
                print("\n☁️  CDK Stack:")
                printStackStatus(status)

            case .stackError(let message):
                print("\n☁️  CDK Stack:")
                print("  Unable to fetch stack status: \(message)")

            case .status:
                break
            }
        }

        private func printStackStatus(_ status: DeployStatusWorkflow.StackStatus) {
            switch status {
            case .deployed(let stack):
                if stack.outputs.isEmpty {
                    print("  Stack deployed but no outputs")
                } else {
                    for (key, value) in stack.outputs.sorted(by: { $0.key < $1.key }) {
                        print("  \(key): \(value)")
                    }
                }
                print("  Infrastructure: DB=\(stack.infrastructure.hasDatabase), NAT=\(stack.infrastructure.hasNATGateway), VPC=\(stack.infrastructure.hasVPC)")
            case .notDeployed:
                print("  Stack not deployed")
            case .credentialExpired(let message):
                print("  ⚠️  Credentials expired: \(message)")
            case .failed(let reason):
                print("  ❌ Stack in failed state: \(reason)")
            case .deploying:
                print("  🔄 Deployment in progress...")
            case .destroying:
                print("  🔄 Destroy in progress...")
            case .unknown(let state):
                print("  State: \(state)")
            }
        }
    }
}
