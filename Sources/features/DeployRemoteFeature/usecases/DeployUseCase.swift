import Foundation
import AWSSDK
import CLISDK
import Uniflow

/// Use case for deploying CDK infrastructure.
/// Orchestrates CDK deployment and CloudFormation monitoring, returning progress via stream.
public struct DeployUseCase: StreamingUseCase {
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

    /// Components needed for deployment operations.
    /// Exposes the CloudFormation client for configuration detection before running the use case.
    public struct Components: Sendable {
        public let useCase: DeployUseCase
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

        let useCase = DeployUseCase(
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

    /// App-specific deployment options
    public struct Options: Sendable {
        public let infrastructure: InfrastructureShape
        public let requireApproval: Bool
        public let output: CLIOutputStream?

        public init(
            infrastructure: InfrastructureShape = .minimal,
            requireApproval: Bool = false,
            output: CLIOutputStream? = nil
        ) {
            self.infrastructure = infrastructure
            self.requireApproval = requireApproval
            self.output = output
        }

        /// Convenience initializer for backward compatibility
        public init(
            withPostgres: Bool = false,
            withNATGateway: Bool = false,
            requireApproval: Bool = false,
            output: CLIOutputStream? = nil
        ) {
            self.infrastructure = InfrastructureShape(
                hasDatabase: withPostgres,
                hasNATGateway: withNATGateway
            )
            self.requireApproval = requireApproval
            self.output = output
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

    /// Stream the deploy use case, yielding state updates during execution.
    /// - Parameter options: Deployment options (including optional output stream)
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

        // Phase 1: CDK Deploy (building + deploying)
        for try await cdkProgress in cdkClient.deployStream(options: options.toCDKOptions(), output: output) {
            switch cdkProgress {
            case .installing, .building:
                continuation.yield(.deploying(UseCaseState.DeployProgress(
                    step: .building,
                    startTime: startTime
                )))

            case .deploying(let progress):
                continuation.yield(.deploying(UseCaseState.DeployProgress(
                    step: .deploying,
                    startTime: startTime,
                    detail: progress
                )))

            case .deployed:
                // CDK CLI has completed, but CloudFormation may still be working
                continuation.yield(.deploying(UseCaseState.DeployProgress(
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
                continuation.yield(.deploying(UseCaseState.DeployProgress(
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
