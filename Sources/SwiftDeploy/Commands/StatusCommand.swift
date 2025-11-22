import Foundation
import ArgumentParser

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
        // Resolve AWS configuration from CLI args and config file
        let awsConfig = try AWSAuthConfiguration.resolve(
            profileName: awsProfile,
            useAWSVault: useAwsVault
        )

        print("📊 Checking status...\n")

        let projectRoot = FileManager.default.currentDirectoryPath
        let deploymentService = DeploymentService(
            projectRoot: projectRoot,
            awsConfig: awsConfig
        )
        let gitService = GitService(repoPath: projectRoot)

        // Git status
        print("📝 Git Status:")
        let hasUncommitted = try await gitService.hasUncommittedChanges()
        print("  Uncommitted changes: \(hasUncommitted ? "YES" : "NO")")

        let hasCommitsToPush = try await gitService.hasCommitsToPush()
        print("  Commits to push: \(hasCommitsToPush ? "YES" : "NO")")

        let currentBranch = try await gitService.getCurrentBranch()
        print("  Current branch: \(currentBranch)")

        // GitHub Actions status
        do {
            let repoInfo = try await gitService.getRepoInfo()
            let githubService = GitHubService(owner: repoInfo.owner, repo: repoInfo.name)
            let (status, conclusion) = try await githubService.getLatestRunStatus(branch: currentBranch)

            print("\n🔄 GitHub Actions:")
            print("  Latest workflow status: \(status)")
            if let conclusion = conclusion {
                print("  Conclusion: \(conclusion)")
            }
        } catch {
            print("\n🔄 GitHub Actions: Unable to fetch status")
        }

        // CDK Stack status
        do {
            let outputs = try await deploymentService.getStackOutputs(
                stackName: "SwiftLambdaSampleStack"
            )

            print("\n☁️  CDK Stack:")
            if !outputs.isEmpty {
                for (key, value) in outputs.sorted(by: { $0.key < $1.key }) {
                    print("  \(key): \(value)")
                }
            } else {
                print("  Stack not found or no outputs")
            }
        } catch {
            print("\n☁️  CDK Stack: Not deployed or error fetching status")
        }
    }
}
