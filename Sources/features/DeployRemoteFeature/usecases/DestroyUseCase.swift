import AWSSDK
import CLISDK
import Foundation
import Uniflow

/// Use case for destroying CDK infrastructure.
/// Orchestrates CDK destroy and CloudFormation monitoring, returning progress via stream.
public struct DestroyUseCase: StreamingUseCase {
    public typealias State = UseCaseState
    public typealias Result = State
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
    /// Exposes the CloudFormation client for state checking before running the use case.
    public struct Components: Sendable {
        public let useCase: DestroyUseCase
        public let cfClient: CloudFormationClient
        public let stackName: String
    }

    /// Creates a use case and associated components by instantiating required clients.
    /// - Parameters:
    ///   - cdkDirectory: Full path to the CDK directory
    ///   - credentialProvider: AWS credential provider for authentication
    ///   - cliClient: CLI client for executing commands
    ///   - stackName: CloudFormation stack name (defaults to CDKStackConfiguration.defaultStackName)
    /// - Returns: Components containing the use case and CloudFormation client
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

        let useCase = DestroyUseCase(
            cdkClient: cdkClient,
            cfClient: cfClient,
            stackName: stackName
        )

        return Components(
            useCase: useCase,
            cfClient: cfClient,
            stackName: stackName
        )
    }

    // Note: This use case yields UseCaseState directly. The use case captures
    // startTime internally; the app layer adds `prior` when needed.

    /// Options for destroying infrastructure
    public struct Options: Sendable {
        /// Skip confirmation prompts (force destroy)
        public let force: Bool
        /// Optional CLI output stream for raw command output
        public let output: CLIOutputStream?

        public init(force: Bool = true, output: CLIOutputStream? = nil) {
            self.force = force
            self.output = output
        }

        func toCDKOptions() -> CDKClient.DestroyOptions {
            CDKClient.DestroyOptions(stackName: nil, force: force)
        }
    }

    /// Stream the destroy use case, yielding state updates during execution.
    /// - Parameter options: Destroy options (including optional output stream)
    /// - Returns: AsyncThrowingStream that yields State updates
    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runUseCase(
                        options: options,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runUseCase(
        options: Options,
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        let output = options.output
        let startTime = Date()

        // Phase 1: CDK Destroy
        for try await cdkProgress in cdkClient.destroyStream(options: options.toCDKOptions(), output: output) {
            switch cdkProgress {
            case .destroying(let progress):
                continuation.yield(.destroying(UseCaseState.DestroyProgress(
                    step: .destroying,
                    startTime: startTime,
                    detail: progress
                )))

            case .destroyed:
                // CDK CLI has completed, but CloudFormation may still be deleting
                continuation.yield(.destroying(UseCaseState.DestroyProgress(
                    step: .destroying,
                    startTime: startTime
                )))

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
                continuation.yield(.destroying(UseCaseState.DestroyProgress(
                    step: .destroying,
                    startTime: startTime,
                    detail: progress
                )))

            case .notDeployed:
                // Stack has been fully deleted
                continuation.yield(.completed(.notDeployed))
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
            continuation.yield(.completed(.notDeployed))
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
