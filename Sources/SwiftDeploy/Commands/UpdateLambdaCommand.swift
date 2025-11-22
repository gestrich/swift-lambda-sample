import Foundation
import ArgumentParser

extension AWSCommand {
    struct UpdateLambdaCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update-lambda",
            abstract: "Update Lambda code only (via GitHub Actions)"
        )

    @Flag(name: .long, help: "Skip git push (manually trigger workflow instead)")
    var skipPush: Bool = false

    mutating func run() async throws {
        print("🚀 Updating Lambda code...\n")

        let projectRoot = FileManager.default.currentDirectoryPath
        let gitService = GitService(repoPath: projectRoot)

        let repoInfo = try await gitService.getRepoInfo()
        let currentBranch = try await gitService.getCurrentBranch()
        let githubService = GitHubService(owner: repoInfo.owner, repo: repoInfo.name)

        if !skipPush {
            let hasCommitsToPush = try await gitService.hasCommitsToPush()

            if hasCommitsToPush {
                // Get the current latest run ID before pushing
                let beforeRunId = try await githubService.getLatestRunId(branch: currentBranch)

                // Push commits (this will auto-trigger the workflow)
                try await gitService.push()

                // Wait for the NEW workflow that was triggered by the push
                try await githubService.waitForNewWorkflowCompletion(
                    branch: currentBranch,
                    afterRunId: beforeRunId,
                    timeoutMinutes: 10
                )
            } else {
                // No commits to push, manually trigger the workflow
                print("✅ No commits to push")
                print("🔄 Triggering workflow to redeploy current code...\n")
                try await githubService.triggerWorkflowAndWait(
                    workflowName: "Dev Deploy",
                    branch: currentBranch,
                    timeoutMinutes: 10
                )
            }
        } else {
            // Skip push, manually trigger the workflow
            print("⏭️  Skipping git push (--skip-push enabled)")
            print("🔄 Triggering workflow...\n")
            try await githubService.triggerWorkflowAndWait(
                workflowName: "Dev Deploy",
                branch: currentBranch,
                timeoutMinutes: 10
            )
        }

        print("\n🎉 Lambda deployment completed successfully!")
    }
    }
}
