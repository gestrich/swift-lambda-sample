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

            let workflow = UpdateLambdaWorkflow(
                gitClient: gitClient,
                githubClient: githubClient
            )

            let options = UpdateLambdaWorkflow.Options(skipPush: skipPush)

            for try await progress in workflow.run(options: options) {
                switch progress.step {
                case .checkingGitStatus:
                    if case .skippedPush = progress.detail {
                        print("\n⏭️  Skipping git push (--skip-push enabled)")
                    }

                case .pushing:
                    break

                case .triggeringWorkflow:
                    if case .gitStatus(let hasCommits) = progress.detail, !hasCommits {
                        print("\n✅ No commits to push")
                    }
                    print("🔄 Triggering workflow...\n")

                case .waitingForWorkflow:
                    break

                case .complete:
                    break
                }
            }

            print("\n🎉 Lambda deployment completed successfully!")
        }
    }
}
