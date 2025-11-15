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
                    // Push commits (this will auto-trigger the workflow)
                    try await gitService.push()

                    // Wait for the workflow that was triggered by the push
                    try await githubService.waitForWorkflowCompletion(
                        branch: currentBranch,
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

        print("\n🎉 Deployment completed successfully!")
    }
}
