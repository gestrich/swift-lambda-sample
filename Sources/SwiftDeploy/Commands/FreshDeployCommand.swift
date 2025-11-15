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

        // 4. Push to remote if needed
        if !skipPush {
            let hasCommitsToPush = try await gitService.hasCommitsToPush()

            if hasCommitsToPush {
                try await gitService.push()

                // 5. Wait for GitHub Actions if we pushed
                if !skipGithubActions {
                    let repoInfo = try await gitService.getRepoInfo()
                    let currentBranch = try await gitService.getCurrentBranch()
                    let githubService = GitHubService(owner: repoInfo.owner, repo: repoInfo.name)

                    try await githubService.waitForWorkflowCompletion(
                        branch: currentBranch,
                        timeoutMinutes: 10
                    )
                }
            } else {
                print("\n✅ No commits to push")

                if !skipGithubActions {
                    // Check if there's already a running workflow
                    let repoInfo = try await gitService.getRepoInfo()
                    let currentBranch = try await gitService.getCurrentBranch()
                    let githubService = GitHubService(owner: repoInfo.owner, repo: repoInfo.name)

                    let (status, conclusion) = try await githubService.getLatestRunStatus(branch: currentBranch)
                    print("\n📊 Latest GitHub Actions workflow: status=\(status), conclusion=\(conclusion ?? "none")")
                }
            }
        }

        print("\n🎉 Deployment completed successfully!")
    }
}
