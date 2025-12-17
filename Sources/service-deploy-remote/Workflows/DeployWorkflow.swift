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

    // Note: This workflow yields WorkflowState directly. The workflow captures
    // startTime internally; the app layer adds `prior` when needed.

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
    /// - Returns: AsyncThrowingStream that yields WorkflowState updates
    public func run(
        options: Options,
        output: CLIOutputStream? = nil
    ) -> AsyncThrowingStream<WorkflowState, Error> {
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
        continuation: AsyncThrowingStream<WorkflowState, Error>.Continuation
    ) async throws {
        let startTime = Date()

        // Phase 1: CDK Deploy (building + deploying)
        for try await cdkProgress in cdkClient.deployStream(options: options.toCDKOptions(), output: output) {
            switch cdkProgress {
            case .installing, .building:
                continuation.yield(.deploying(WorkflowState.DeployProgress(
                    step: .building,
                    startTime: startTime
                )))

            case .deploying(let progress):
                continuation.yield(.deploying(WorkflowState.DeployProgress(
                    step: .deploying,
                    startTime: startTime,
                    detail: progress
                )))

            case .deployed:
                // CDK CLI has completed, but CloudFormation may still be working
                continuation.yield(.deploying(WorkflowState.DeployProgress(
                    step: .monitoring,
                    startTime: startTime
                )))

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
                continuation.yield(.deploying(WorkflowState.DeployProgress(
                    step: .monitoring,
                    startTime: startTime,
                    detail: progress
                )))

            case .deployed(let stack):
                let snapshot = DeploymentSnapshot(
                    status: .deployed(stack),
                    outputs: CDKStackOutputs.from(stack.outputs),
                    infrastructure: CDKInfrastructureConfiguration(stack.infrastructure)
                )
                continuation.yield(.completed(snapshot))
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
            let snapshot = DeploymentSnapshot(
                status: .deployed(stack),
                outputs: CDKStackOutputs.from(stack.outputs),
                infrastructure: CDKInfrastructureConfiguration(stack.infrastructure)
            )
            continuation.yield(.completed(snapshot))
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
