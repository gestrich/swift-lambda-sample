import Foundation
import c_service_deploy_local
import CLISDK

/// Workflow for starting Lambda with all services for Linux development.
public struct LinuxStartAllWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public init(service: LinuxLocalDevelopmentService) {
        self.service = service
    }

    /// Progress updates from the start all workflow.
    public struct Progress: Sendable {
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
            case servicesProgress(LinuxStartServicesWorkflow.Progress)
            case networkProgress(LinuxSetupNetworkWorkflow.Progress)
            case lambdaProgress(LinuxStartLambdaWorkflow.Progress)
            case port(Int)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    /// Run the start all workflow.
    /// - Returns: AsyncThrowingStream that yields Progress updates
    public func run() -> AsyncThrowingStream<Progress, Error> {
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
        continuation: AsyncThrowingStream<Progress, Error>.Continuation
    ) async throws {
        // Start services first
        continuation.yield(Progress(step: .startingServices))
        let servicesWorkflow = LinuxStartServicesWorkflow(service: service)
        for try await servicesProgress in servicesWorkflow.run() {
            continuation.yield(Progress(
                step: .startingServices,
                detail: .servicesProgress(servicesProgress)
            ))
        }

        // Setup Docker network
        continuation.yield(Progress(step: .setupNetwork))
        let networkWorkflow = LinuxSetupNetworkWorkflow(service: service)
        for try await networkProgress in networkWorkflow.run() {
            continuation.yield(Progress(
                step: .setupNetwork,
                detail: .networkProgress(networkProgress)
            ))
        }

        // Then start Lambda container
        continuation.yield(Progress(step: .startingLambda))
        let lambdaWorkflow = LinuxStartLambdaWorkflow(service: service)
        for try await lambdaProgress in lambdaWorkflow.run() {
            continuation.yield(Progress(
                step: .startingLambda,
                detail: .lambdaProgress(lambdaProgress)
            ))
        }

        // Wait for Lambda to be ready
        continuation.yield(Progress(step: .waitingForReady))
        try await service.waitForReady()

        let port = await service.port
        continuation.yield(Progress(step: .complete, detail: .port(port)))
        continuation.finish()
    }
}
