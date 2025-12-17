import ArgumentParser
import Foundation
import sdk_cli
import service_deploy

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
            let cliClient = CLIClient(defaultWorkingDirectory: projectRoot)

            let workflow = try UpdateLambdaWorkflow.create(
                projectRoot: projectRoot,
                cliClient: cliClient
            )

            let options = UpdateLambdaWorkflow.Options(skipPush: skipPush)

            for try await state in workflow.run(options: options) {
                switch state {
                case .updatingLambda(let progress):
                    switch progress.step {
                    case .checkingGitStatus:
                        print("Checking git status...")

                    case .pushing:
                        print("Pushing commits...")

                    case .triggeringWorkflow:
                        print("🔄 Triggering workflow...\n")

                    case .waitingForWorkflow:
                        print("Waiting for GitHub Actions workflow...")

                    case .monitoringWorkflow(let runId):
                        if let detail = progress.runDetail {
                            print("Monitoring workflow \(runId): \(detail.status)")
                        } else {
                            print("Monitoring workflow \(runId)...")
                        }
                    }

                case .completed, .deploying, .destroying:
                    break
                }
            }

            print("\n🎉 Lambda deployment completed successfully!")
        }
    }
}
