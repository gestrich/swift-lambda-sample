import Foundation
import ArgumentParser

struct DeployCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deploy",
        abstract: "Deploy CDK infrastructure and optionally update Lambda code"
    )

    @Option(name: .long, help: "AWS profile to use")
    var awsProfile: String = "production"

    @Option(name: .long, help: "CDK directory path")
    var cdkDirectory: String = "cdk"

    @Flag(name: .long, help: "Include PostgreSQL database (adds cost)")
    var withPostgres: Bool = false

    @Flag(name: .long, help: "Include NAT Gateway (adds cost)")
    var withNatGateway: Bool = false

    @Flag(name: .long, help: "Skip Lambda code deployment (CDK infrastructure only)")
    var infraOnly: Bool = false

    @Flag(name: .long, help: "Skip git push")
    var skipPush: Bool = false

    mutating func run() async throws {
        print("🚀 Starting deployment...\n")

        if !withPostgres && !withNatGateway {
            print("💰 MINIMAL COST MODE (default)")
            print("   - No PostgreSQL database")
            print("   - No NAT Gateway")
            print("   - Cost: ~$0/month (only pay for Lambda invocations, S3, SQS usage)")
            print("")
        }

        let projectRoot = FileManager.default.currentDirectoryPath
        let deploymentService = DeploymentService(projectRoot: projectRoot)
        let gitService = GitService(repoPath: projectRoot)

        // 1. Deploy CDK infrastructure
        let options = DeploymentOptions(
            skipPostgres: !withPostgres,  // Invert: default is to skip
            skipNATGateway: !withNatGateway,  // Invert: default is to skip
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

        // 4. Deploy Lambda code via GitHub Actions (unless --infra-only)
        if !infraOnly {
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
            // Infrastructure-only deployment
            print("\n⏭️  Skipping Lambda code deployment (--infra-only enabled)")
            print("⚠️  Lambda code was NOT deployed. Use 'deploy-lambda' to update Lambda code.")
        }

        // 5. Verify deployment by testing the API
        if !infraOnly {
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
