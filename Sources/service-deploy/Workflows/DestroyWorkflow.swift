import Foundation
import sdk_aws
import sdk_cli

/// Workflow for destroying CDK infrastructure.
/// Orchestrates CDK destroy and CloudFormation monitoring, returning progress via stream.
public struct DestroyWorkflow: Sendable {
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

    /// Components needed for destroy operations.
    /// Exposes the CloudFormation client for state checking before running the workflow.
    public struct Components: Sendable {
        public let workflow: DestroyWorkflow
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

        let workflow = DestroyWorkflow(
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

    /// Progress updates from the destroy workflow
    public struct Progress: Sendable {
        public let step: Step
        public let detail: DeploymentProgress?

        public enum Step: Sendable, Equatable {
            case destroying
            case complete
        }

        public init(step: Step, detail: DeploymentProgress? = nil) {
            self.step = step
            self.detail = detail
        }

        /// Converts workflow progress to CloudFormation state for UI display.
        /// This moves the mapping logic from the app layer (DeploymentModel) to the service layer.
        /// - Parameter startTime: Operation start time for elapsed time display
        /// - Returns: CloudFormationState representing the current destroy state
        public func toDeploymentState(startTime: Date) -> CloudFormationState {
            switch step {
            case .destroying:
                return .destroying(progress: detail ?? DeploymentProgress(), startTime: startTime)
            case .complete:
                return .notDeployed
            }
        }
    }

    /// Options for destroying infrastructure
    public struct Options: Sendable {
        /// Skip confirmation prompts (force destroy)
        public let force: Bool

        public init(force: Bool = true) {
            self.force = force
        }

        func toCDKOptions() -> CDKClient.DestroyOptions {
            CDKClient.DestroyOptions(stackName: nil, force: force)
        }
    }

    /// Run the destroy workflow
    /// - Parameters:
    ///   - options: Destroy options
    ///   - output: Optional CLI output stream for raw command output
    /// - Returns: AsyncThrowingStream that yields Progress updates
    public func run(
        options: Options = Options(),
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
        // Phase 1: CDK Destroy
        for try await cdkProgress in cdkClient.destroyStream(options: options.toCDKOptions(), output: output) {
            switch cdkProgress {
            case .destroying(let progress):
                continuation.yield(Progress(step: .destroying, detail: progress))

            case .destroyed:
                // CDK CLI has completed, but CloudFormation may still be deleting
                continuation.yield(Progress(step: .destroying))

            case .installing, .building, .deploying, .deployed:
                // Shouldn't happen during destroy, but handle gracefully
                break
            }
        }

        // Phase 2: Monitor CloudFormation until destroy is complete
        // CDK may return before CloudFormation finishes deleting all resources
        for try await cfState in cfClient.monitorStream(stackName: stackName) {
            switch cfState {
            case .destroying(let progress, _):
                continuation.yield(Progress(step: .destroying, detail: progress))

            case .notDeployed:
                // Stack has been fully deleted
                continuation.yield(Progress(step: .complete))
                continuation.finish()
                return

            case .failed(let reason):
                throw DeploymentError.deploymentFailed(reason: "Destroy failed: \(reason)")

            case .credentialExpired(let message):
                throw DeploymentError.credentialExpired(message: message)

            case .deploying, .deployed, .loading, .unknown:
                // Continue monitoring
                break
            }
        }

        // If we get here, stream ended without completing
        // Query final state to determine outcome
        let finalState = try await cfClient.queryState(stackName: stackName)
        switch finalState {
        case .notDeployed:
            continuation.yield(Progress(step: .complete))
            continuation.finish()

        case .failed(let reason):
            throw DeploymentError.deploymentFailed(reason: "Destroy failed: \(reason)")

        case .credentialExpired(let message):
            throw DeploymentError.credentialExpired(message: message)

        case .destroying:
            // Still destroying - this shouldn't happen if monitorStream completed
            throw DeploymentError.operationInProgress(operation: "DELETE_IN_PROGRESS")

        default:
            throw DeploymentError.unknown(message: "Unexpected final state after destroy: \(finalState)")
        }
    }
}
