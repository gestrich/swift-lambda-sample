import Foundation
import ArgumentParser

struct DeployCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deploy",
        abstract: "Deploy/update CDK infrastructure only (does not update Lambda code)"
    )

    @Option(name: .long, help: "AWS profile to use")
    var awsProfile: String = "production"

    @Option(name: .long, help: "CDK directory path")
    var cdkDirectory: String = "cdk"

    @Flag(name: .long, help: "Include PostgreSQL database (adds cost)")
    var withPostgres: Bool = false

    @Flag(name: .long, help: "Include NAT Gateway (adds cost)")
    var withNatGateway: Bool = false

    mutating func run() async throws {
        print("🚀 Deploying CDK infrastructure...\n")

        if !withPostgres && !withNatGateway {
            print("💰 MINIMAL COST MODE (default)")
            print("   - No PostgreSQL database")
            print("   - No NAT Gateway")
            print("   - Cost: ~$0/month (only pay for Lambda invocations, S3, SQS usage)")
            print("")
        }

        let projectRoot = FileManager.default.currentDirectoryPath
        let deploymentService = DeploymentService(projectRoot: projectRoot)

        // 1. Deploy CDK infrastructure
        let options = DeploymentOptions(
            skipPostgres: !withPostgres,
            skipNATGateway: !withNatGateway,
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

        print("\n✅ Infrastructure deployment completed successfully!")
        print("\nℹ️  Lambda code was NOT updated. Use 'update-lambda' to update Lambda code.")
    }
}
