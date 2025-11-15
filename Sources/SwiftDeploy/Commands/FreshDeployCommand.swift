import Foundation
import ArgumentParser

struct FreshDeployCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fresh-deploy",
        abstract: "Deploy CDK stack and wait for GitHub Actions to complete"
    )

    @Option(name: .long, help: "AWS profile to use")
    var awsProfile: String = "production"

    @Option(name: .long, help: "CDK directory path")
    var cdkDirectory: String = "cdk"

    @Flag(name: .long, help: "Skip PostgreSQL database deployment")
    var skipPostgres: Bool = false

    @Flag(name: .long, help: "Skip NAT Gateway deployment")
    var skipNatGateway: Bool = false

    @Flag(name: .long, help: "Skip waiting for GitHub Actions workflow")
    var skipGithubActions: Bool = false

    @Flag(name: .long, help: "Skip git push")
    var skipPush: Bool = false

    mutating func run() async throws {
        print("🚀 Starting fresh deployment...\n")

        let projectRoot = FileManager.default.currentDirectoryPath
        let deploymentService = DeploymentService(projectRoot: projectRoot)
        let gitService = GitService(repoPath: projectRoot)

        // 1. Deploy CDK
        let options = DeploymentOptions(
            skipPostgres: skipPostgres,
            skipNATGateway: skipNatGateway,
            awsProfile: awsProfile,
            cdkDirectory: cdkDirectory
        )

        try await deploymentService.deploy(options: options)

        // 2. Poll deployment status
        try await deploymentService.pollDeploymentStatus(
            stackName: "SwiftLambdaSampleStack",
            awsProfile: awsProfile
        )

        // 3. Get and display stack outputs
        let outputs = try await deploymentService.getStackOutputs(
            stackName: "SwiftLambdaSampleStack",
            awsProfile: awsProfile
        )

        if !outputs.isEmpty {
            print("\n📋 Stack Outputs:")
            for (key, value) in outputs.sorted(by: { $0.key < $1.key }) {
                print("  \(key): \(value)")
            }
        }

        // 4. Deploy Lambda code via GitHub Actions
        if !skipGithubActions {
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
                    // No commits to push, but we still need to deploy Lambda code
                    // Manually trigger the workflow
                    print("\n✅ No commits to push")
                    try await githubService.triggerWorkflowAndWait(
                        workflowName: "Dev Deploy",
                        branch: currentBranch,
                        timeoutMinutes: 10
                    )
                }
            } else {
                // Skip push is enabled, but we still need Lambda code deployed
                // Manually trigger the workflow
                print("\n⏭️  Skipping git push (--skip-push enabled)")
                try await githubService.triggerWorkflowAndWait(
                    workflowName: "Dev Deploy",
                    branch: currentBranch,
                    timeoutMinutes: 10
                )
            }
        } else {
            // GitHub Actions are skipped entirely
            if !skipPush {
                let hasCommitsToPush = try await gitService.hasCommitsToPush()
                if hasCommitsToPush {
                    try await gitService.push()
                } else {
                    print("\n✅ No commits to push")
                }
            }
            print("\n⚠️  Skipping GitHub Actions deployment (--skip-github-actions enabled)")
            print("⚠️  Lambda code was NOT deployed. You'll need to deploy it manually.")
        }

        // 5. Verify deployment by testing the API
        if !skipGithubActions {
            print("\n🧪 Verifying deployment...")

            do {
                try await verifyDeployment(
                    stackName: "SwiftLambdaSampleStack",
                    awsProfile: awsProfile
                )
                print("\n✅ Deployment verification passed!")
            } catch {
                print("\n⚠️  Deployment verification failed: \(error)")
                print("⚠️  The infrastructure is deployed but the API may not be working correctly.")
            }
        }

        print("\n🎉 Deployment completed successfully!")
    }

    private func verifyDeployment(stackName: String, awsProfile: String) async throws {
        let projectRoot = FileManager.default.currentDirectoryPath
        let deploymentService = DeploymentService(projectRoot: projectRoot)
        let cliService = CLIService.shared

        // Get API Gateway URL
        let outputs = try await deploymentService.getStackOutputs(
            stackName: stackName,
            awsProfile: awsProfile
        )

        guard let apiUrl = outputs["ApiGatewayUrl"] else {
            throw CLIError.invalidOutput(reason: "Could not find ApiGatewayUrl in stack outputs")
        }

        // Test the file endpoint
        print("  Testing S3 file endpoint...")
        print("  → POST \(apiUrl)api/file")

        let testResult = try await cliService.execute(
            command: "curl",
            arguments: [
                "-s",
                "-X", "POST",
                "\(apiUrl)api/file"
            ],
            printCommand: false
        )

        guard testResult.isSuccess else {
            throw CLIError.executionFailed(
                command: "curl",
                exitCode: testResult.exitCode,
                stderr: testResult.stderr
            )
        }

        let response = testResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        print("  Response: \(response)")

        if !response.contains("File uploaded and downloaded") {
            throw CLIError.deploymentFailed(reason: "Unexpected API response: \(response)")
        }

        print("  ✓ API Gateway working")
        print("  ✓ Lambda function executing")
        print("  ✓ S3 integration working")
    }
}
