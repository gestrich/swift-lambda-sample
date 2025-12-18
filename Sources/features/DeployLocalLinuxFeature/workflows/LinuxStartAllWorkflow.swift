import Foundation
import DeployLocalService
import CLISDK
import Uniflow

/// Workflow for starting Lambda with all services for Linux development.
public struct LinuxStartAllWorkflow: StreamingWorkflow {
    private let service: LinuxLocalDevelopmentService

    public init(service: LinuxLocalDevelopmentService) {
        self.service = service
    }

    /// State updates from the start all workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case startingServices
            case setupNetwork
            case startingLambda
            case waitingForReady
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case servicesState(LinuxStartServicesWorkflow.State)
            case networkState(LinuxSetupNetworkWorkflow.State)
            case lambdaState(LinuxStartLambdaWorkflow.State)
            case port(Int)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State
    public typealias Options = Void

    /// Stream the start all workflow.
    /// - Returns: AsyncThrowingStream that yields State updates
    public func stream(options: Void) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        // Start services first
        continuation.yield(State(step: .startingServices))
        let servicesWorkflow = LinuxStartServicesWorkflow(service: service)
        for try await servicesState in servicesWorkflow.stream(options: .all) {
            continuation.yield(State(
                step: .startingServices,
                detail: .servicesState(servicesState)
            ))
        }

        // Setup Docker network
        continuation.yield(State(step: .setupNetwork))
        let networkWorkflow = LinuxSetupNetworkWorkflow(service: service)
        for try await networkState in networkWorkflow.stream() {
            continuation.yield(State(
                step: .setupNetwork,
                detail: .networkState(networkState)
            ))
        }

        // Then start Lambda container
        continuation.yield(State(step: .startingLambda))
        let lambdaWorkflow = LinuxStartLambdaWorkflow(service: service)
        for try await lambdaState in lambdaWorkflow.stream() {
            continuation.yield(State(
                step: .startingLambda,
                detail: .lambdaState(lambdaState)
            ))
        }

        // Wait for Lambda to be ready
        continuation.yield(State(step: .waitingForReady))
        try await service.waitForReady()

        let port = await service.port
        continuation.yield(State(step: .complete, detail: .port(port)))
        continuation.finish()
    }
}
