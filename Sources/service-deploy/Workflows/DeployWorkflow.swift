import Foundation
import sdk_aws
import sdk_cli

/// Workflow for deploying CDK infrastructure.
/// Orchestrates CDK deployment and CloudFormation monitoring, returning progress via stream.
public struct DeployWorkflow: Sendable {
    private let cdkClient: CDKClient
    private let cfClient: CloudFormationClient
    private let stackName: String

    public init(
        cdkClient: CDKClient,
        cfClient: CloudFormationClient,
        stackName: String
    ) {
        self.cdkClient = cdkClient
        self.cfClient = cfClient
        self.stackName = stackName
    }

    /// Components needed for deployment operations.
    /// Exposes the CloudFormation client for configuration detection before running the workflow.
    public struct Components: Sendable {
        public let workflow: DeployWorkflow
        public let cfClient: CloudFormationClient
        public let stackName: String
    }

    /// Creates a workflow and associated components by instantiating required clients.
    /// - Parameters:
    ///   - cdkDirectory: Full path to the CDK directory
    ///   - credentialProvider: AWS credential provider for authentication
    ///   - cliClient: CLI client for executing commands
    ///   - stackName: CloudFormation stack name (defaults to CDKStackConfiguration.defaultStackName)
    /// - Returns: Components containing the workflow and CloudFormation client
    public static func create(
        cdkDirectory: String,
        credentialProvider: any AWSCredentialProvider,
        cliClient: CLIClient,
        stackName: String = CDKStackConfiguration.defaultStackName
    ) -> Components {
        let cdkClient = CDKClient(
            cdkDirectory: cdkDirectory,
            credentialProvider: credentialProvider,
            cliClient: cliClient
        )
        let cfClient = CloudFormationClient(
            credentialProvider: credentialProvider,
            cliClient: cliClient
        )

        let workflow = DeployWorkflow(
            cdkClient: cdkClient,
            cfClient: cfClient,
            stackName: stackName
        )

        return Components(
            workflow: workflow,
            cfClient: cfClient,
            stackName: stackName
        )
    }

    /// Progress updates from the deploy workflow.
    ///
    /// This is the service-layer progress type that tracks workflow phases:
    /// building → deploying → monitoring → complete
    ///
    /// The `Detail` enum wraps SDK-layer progress (`DeploymentProgress`) and
    /// adds workflow-specific context like final outputs and configuration.
    ///
    /// ## Progress Type Hierarchy
    ///
    /// This type aggregates SDK-layer progress for consumption by the app layer:
    ///
    /// ```
    /// DeploymentProgress (sdk-aws) - individual resources
    ///     └── embedded in CloudFormationState (sdk-aws) - stack lifecycle
    ///         └── consumed by DeployWorkflow.Progress (service-deploy) ← YOU ARE HERE
    ///             └── consumed by ActiveWorkflow (feature-mac) - UI state
    /// ```
    ///
    /// ## Consumers
    ///
    /// - CLI commands (print progress directly)
    /// - `DeploymentModel.activeWorkflow` (UI binding)
    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case building
            case deploying
            case monitoring
            case complete
        }

        public enum Detail: Sendable {
            case cdk(DeploymentProgress)
            case outputs(CDKStackOutputs?, CDKInfrastructureConfiguration?)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }

        /// Converts workflow progress to CloudFormation state for UI display.
        /// This moves the mapping logic from the app layer (DeploymentModel) to the service layer.
        /// - Parameter startTime: Operation start time for elapsed time display
        /// - Returns: CloudFormationState representing the current deployment state
        public func toDeploymentState(startTime: Date) -> CloudFormationState {
            switch step {
            case .building:
                return .deploying(operation: .building, progress: DeploymentProgress(), startTime: startTime)

            case .deploying:
                let deployProgress: DeploymentProgress
                if case .cdk(let progress) = detail {
                    deployProgress = progress
                } else {
                    deployProgress = DeploymentProgress()
                }
                return .deploying(operation: .deploying, progress: deployProgress, startTime: startTime)

            case .monitoring:
                let deployProgress: DeploymentProgress
                if case .cdk(let progress) = detail {
                    deployProgress = progress
                } else {
                    deployProgress = DeploymentProgress()
                }
                return .deploying(operation: .monitoring, progress: deployProgress, startTime: startTime)

            case .complete:
                if case .outputs(let outputs, let config) = detail {
                    let stack = DeployedStack(
                        outputs: outputs?.allOutputs ?? [:],
                        infrastructure: config?.detectedInfrastructure ?? DetectedInfrastructure()
                    )
                    return .deployed(stack)
                }
                return .deployed(DeployedStack())
            }
        }

        /// Extracts stack outputs from the progress detail, if available.
        public var stackOutputs: CDKStackOutputs? {
            if case .outputs(let outputs, _) = detail {
                return outputs
            }
            return nil
        }

        /// Extracts infrastructure configuration from the progress detail, if available.
        public var infrastructureConfiguration: CDKInfrastructureConfiguration? {
            if case .outputs(_, let config) = detail {
                return config
            }
            return nil
        }
    }

    /// App-specific deployment options
    public struct Options: Sendable {
        public let infrastructure: InfrastructureShape
        public let requireApproval: Bool

        public init(
            infrastructure: InfrastructureShape = .minimal,
            requireApproval: Bool = false
        ) {
            self.infrastructure = infrastructure
            self.requireApproval = requireApproval
        }

        /// Convenience initializer for backward compatibility
        public init(
            withPostgres: Bool = false,
            withNATGateway: Bool = false,
            requireApproval: Bool = false
        ) {
            self.infrastructure = InfrastructureShape(
                hasDatabase: withPostgres,
                hasNATGateway: withNATGateway
            )
            self.requireApproval = requireApproval
        }

        public static var minimal: Options {
            Options(infrastructure: .minimal)
        }

        public static var full: Options {
            Options(infrastructure: .full)
        }

        func toCDKOptions() -> CDKClient.DeployOptions {
            var context: [String: String] = [:]
            if !infrastructure.hasDatabase {
                context["skipPostgres"] = "true"
            }
            if !infrastructure.hasNATGateway {
                context["skipNATGateway"] = "true"
            }
            return CDKClient.DeployOptions(
                stackName: nil,
                context: context,
                requireApproval: requireApproval,
                outputsFile: nil
            )
        }
    }

    /// Run the deploy workflow
    /// - Parameters:
    ///   - options: Deployment options
    ///   - output: Optional CLI output stream for raw command output
    /// - Returns: AsyncThrowingStream that yields Progress updates
    public func run(
        options: Options,
        output: CLIOutputStream? = nil
    ) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(
                        options: options,
                        output: output,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        options: Options,
        output: CLIOutputStream?,
        continuation: AsyncThrowingStream<Progress, Error>.Continuation
    ) async throws {
        // Phase 1: CDK Deploy (building + deploying)
        for try await cdkProgress in cdkClient.deployStream(options: options.toCDKOptions(), output: output) {
            switch cdkProgress {
            case .installing, .building:
                continuation.yield(Progress(step: .building))

            case .deploying(let progress):
                continuation.yield(Progress(step: .deploying, detail: .cdk(progress)))

            case .deployed:
                // CDK CLI has completed, but CloudFormation may still be working
                continuation.yield(Progress(step: .monitoring))

            case .destroying, .destroyed:
                // Shouldn't happen during deploy, but handle gracefully
                break
            }
        }

        // Phase 2: Monitor CloudFormation until complete
        // CDK may return before CloudFormation finishes all resources
        for try await cfState in cfClient.monitorStream(stackName: stackName) {
            switch cfState {
            case .deploying(_, let progress, _):
                continuation.yield(Progress(step: .monitoring, detail: .cdk(progress)))

            case .deployed(let stack):
                let stackOutputs = CDKStackOutputs.from(stack.outputs)
                continuation.yield(Progress(
                    step: .complete,
                    detail: .outputs(stackOutputs, CDKInfrastructureConfiguration(stack.infrastructure))
                ))
                continuation.finish()
                return

            case .failed(let reason):
                throw DeploymentError.deploymentFailed(reason: reason)

            case .credentialExpired(let message):
                throw DeploymentError.credentialExpired(message: message)

            case .notDeployed:
                throw DeploymentError.stackNotFound(stackName: stackName)

            case .destroying, .loading, .unknown:
                // Continue monitoring
                break
            }
        }

        // If we get here, stream ended without completing
        // Query final state to determine outcome
        let finalState = try await cfClient.queryState(stackName: stackName)
        switch finalState {
        case .deployed(let stack):
            let stackOutputs = CDKStackOutputs.from(stack.outputs)
            continuation.yield(Progress(
                step: .complete,
                detail: .outputs(stackOutputs, CDKInfrastructureConfiguration(stack.infrastructure))
            ))
            continuation.finish()

        case .failed(let reason):
            throw DeploymentError.deploymentFailed(reason: reason)

        case .credentialExpired(let message):
            throw DeploymentError.credentialExpired(message: message)

        default:
            throw DeploymentError.unknown(message: "Unexpected final state: \(finalState)")
        }
    }
}
