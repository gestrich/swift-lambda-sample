import CLIKit
import Foundation

/// AWS CDK CLI program definition using macro-based API
@CLIProgram
public struct Cdk {

    // MARK: - Deploy

    /// CDK deploy command
    /// Example: cdk deploy --profile prod --require-approval never --context skipPostgres=true
    @CLICommand
    public struct Deploy {
        /// AWS profile to use
        @Option public var profile: String?

        /// Approval mode (never, broadening, any-change)
        @Option public var requireApproval: String?

        /// Context key-value pairs (variadic: each item gets its own --context flag)
        @Option("--context") public var context: [String]

        /// Output file for stack outputs
        @Option public var outputsFile: String?
    }

    // MARK: - Destroy

    /// CDK destroy command
    /// Example: cdk destroy --profile prod --force
    @CLICommand
    public struct Destroy {
        /// AWS profile to use
        @Option public var profile: String?

        /// Force destruction without prompts
        @Flag public var force: Bool = false
    }

    // MARK: - Diff

    /// CDK diff command
    /// Example: cdk diff --profile prod
    @CLICommand
    public struct Diff {
        /// AWS profile to use
        @Option public var profile: String?
    }

    // MARK: - Synth

    /// CDK synth command
    /// Example: cdk synth --profile prod
    @CLICommand
    public struct Synth {
        /// AWS profile to use
        @Option public var profile: String?
    }

    // MARK: - List

    /// CDK list command
    /// Example: cdk list --profile prod
    @CLICommand
    public struct List {
        /// AWS profile to use
        @Option public var profile: String?
    }

    // MARK: - Bootstrap

    /// CDK bootstrap command
    /// Example: cdk bootstrap --profile prod
    @CLICommand
    public struct Bootstrap {
        /// AWS profile to use
        @Option public var profile: String?
    }
}
