import Foundation
import ArgumentParser
import service_deploy
import sdk_cli
import sdk_github

extension AWSCommand {
    struct UpdateLambdaCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update-lambda",
            abstract: "Update Lambda code only (via GitHub Actions)"
        )

        @ArgumentParser.Flag(name: .long, help: "Skip git push (manually trigger workflow instead)")
        var skipPush: Bool = false

        mutating func run() async throws {
            print("🚀 Updating Lambda code...\n")

            let projectRoot = FileManager.default.currentDirectoryPath

            guard let githubConfig = GitHubConfiguration.loadConfig()?.toSDKConfiguration() else {
                throw DeployError.configurationMissing(
                    file: GitHubConfiguration.configPath,
                    hint: "Create with: {\"repository\": \"owner/repo\", \"branch\": \"dev\"}"
                )
            }

            let cliClient = CLIClient(defaultWorkingDirectory: projectRoot)
            let gitClient = GitClient(repoPath: projectRoot, cliClient: cliClient)
            let githubClient = GitHubActionsClient(
                repoPath: projectRoot,
                config: githubConfig,
                cliClient: cliClient
            )

            if !skipPush {
                let hasCommitsToPush = try await gitClient.hasCommitsToPush()

                if hasCommitsToPush {
                    let beforeRunId = try await githubClient.getLatestRunId()
                    try await gitClient.push()

                    try await githubClient.waitForNewWorkflowCompletion(
                        afterRunId: beforeRunId,
                        timeoutMinutes: 10
                    )
                } else {
                    print("\n✅ No commits to push")
                    print("🔄 Triggering workflow to redeploy current code...\n")
                    try await githubClient.triggerWorkflowAndWait(
                        workflowName: "Dev Deploy",
                        timeoutMinutes: 10
                    )
                }
            } else {
                print("\n⏭️  Skipping git push (--skip-push enabled)")
                print("🔄 Triggering workflow...\n")
                try await githubClient.triggerWorkflowAndWait(
                    workflowName: "Dev Deploy",
                    timeoutMinutes: 10
                )
            }

            print("\n🎉 Lambda deployment completed successfully!")
        }
    }
}
