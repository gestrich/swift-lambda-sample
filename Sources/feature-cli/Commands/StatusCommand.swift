import ArgumentParser
import Foundation
import sdk_aws
import service_deploy

extension AWSCommand {
    struct StatusCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Check deployment and git status"
        )

        @Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
        var awsProfile: String?

        @Option(name: .long, help: "Use aws-vault for credential management")
        var useAwsVault: Bool?

        mutating func run() async throws {
            let awsConfig = try AWSAuthConfiguration.resolve(
                profileName: awsProfile,
                useAWSVault: useAwsVault
            )

            print("📊 Checking status...\n")

            let projectRoot = FileManager.default.currentDirectoryPath
            try await runStatus(projectRoot: projectRoot, awsConfig: awsConfig)
        }

        @MainActor
        private func runStatus(projectRoot: String, awsConfig: AWSAuthConfiguration) async throws {
            let service = DeploymentService(
                projectRoot: projectRoot,
                awsConfig: awsConfig
            )

            let status = try await service.getComprehensiveStatus()

            print("📝 Git Status:")
            print("  Uncommitted changes: \(status.gitStatus.hasUncommittedChanges ? "YES" : "NO")")
            print("  Commits to push: \(status.gitStatus.hasCommitsToPush ? "YES" : "NO")")
            print("  Current branch: \(status.gitStatus.currentBranch)")

            if let github = status.githubStatus {
                print("\n🔄 GitHub Actions:")
                print("  Repository: \(github.repository)")
                print("  Branch: \(github.branch)")
                print("  Latest workflow status: \(github.latestRunStatus)")
                if let conclusion = github.conclusion {
                    print("  Conclusion: \(conclusion)")
                }
            } else if GitHubConfiguration.loadConfig() == nil {
                print("\n🔄 GitHub Actions: Not configured")
                print("  Create \(GitHubConfiguration.configPath) with:")
                print("  {\"repository\": \"owner/repo\", \"branch\": \"dev\"}")
            } else {
                print("\n🔄 GitHub Actions: Unable to fetch status")
            }

            print("\n☁️  CDK Stack:")
            if !status.stackOutputs.isEmpty {
                for (key, value) in status.stackOutputs.sorted(by: { $0.key < $1.key }) {
                    print("  \(key): \(value)")
                }
            } else {
                print("  Stack not found or no outputs")
            }
        }
    }
}
