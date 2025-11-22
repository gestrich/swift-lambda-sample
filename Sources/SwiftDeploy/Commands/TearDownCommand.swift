import Foundation
import ArgumentParser

struct TearDownCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tear-down",
        abstract: "Destroy the CDK deployment"
    )

    @Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
    var awsProfile: String?

    @Option(name: .long, help: "CDK directory path")
    var cdkDirectory: String = "cdk"

    @Flag(name: .long, help: "Skip confirmation prompt")
    var force: Bool = false

    mutating func run() async throws {
        // Get AWS profile from flag or config file
        let profile = try AWSAuthConfiguration.getProfile(from: awsProfile)

        print("🗑️  Starting tear down...\n")

        if !force {
            print("⚠️  This will destroy the entire CDK stack and all associated resources.")
            print("   Are you sure you want to continue? (yes/no): ", terminator: "")

            guard let response = readLine()?.lowercased(),
                  response == "yes" || response == "y" else {
                print("Cancelled.")
                return
            }
        }

        let projectRoot = FileManager.default.currentDirectoryPath
        let deploymentService = DeploymentService(projectRoot: projectRoot, awsProfile: profile)

        try await deploymentService.tearDown(
            cdkDirectory: cdkDirectory
        )

        print("\n🎉 Tear down completed successfully!")
    }
}
