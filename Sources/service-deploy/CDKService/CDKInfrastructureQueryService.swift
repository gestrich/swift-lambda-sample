import sdk_cli
import Foundation

/// Stateful service for CDK Infrastructure queries and operations
/// Owns the infrastructure state and exposes it via AsyncStream for observers
public actor CDKInfrastructureQueryService {

    // MARK: - State Definition

    /// High-level infrastructure state exposed to observers
    public enum State: Sendable, Equatable {
        case unknown
        case loading
        case notDeployed
        case deployed(configuration: CDKInfrastructureConfiguration, outputs: CDKStackOutputs)
        case deploying(operation: String, progress: CDKDeploymentProgress, startTime: Date)
        case destroying(progress: CDKDeploymentProgress, startTime: Date)
        case failed(reason: String)
        case credentialExpired(message: String)

        public var isBusy: Bool {
            switch self {
            case .loading, .deploying, .destroying:
                return true
            default:
                return false
            }
        }

        public var canDeploy: Bool {
            switch self {
            case .loading, .deploying, .destroying:
                return false
            default:
                return true
            }
        }

        public var canDestroy: Bool {
            switch self {
            case .deployed:
                return true
            default:
                return false
            }
        }

        public var configuration: CDKInfrastructureConfiguration {
            if case .deployed(let config, _) = self {
                return config
            }
            return CDKInfrastructureConfiguration()
        }

        public var outputs: CDKStackOutputs {
            if case .deployed(_, let outputs) = self {
                return outputs
            }
            return CDKStackOutputs()
        }

        public var progress: CDKDeploymentProgress {
            switch self {
            case .deploying(_, let progress, _), .destroying(let progress, _):
                return progress
            default:
                return CDKDeploymentProgress()
            }
        }

        public var operationStartTime: Date? {
            switch self {
            case .deploying(_, _, let startTime), .destroying(_, let startTime):
                return startTime
            default:
                return nil
            }
        }
    }

    // MARK: - Private State

    private var state: State = .unknown
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]
    private let stackName: String

    // MARK: - Services

    private let cdkService: CDKService
    private let awsService: AWSCLIService

    // MARK: - Initialization

    public init(
        projectRoot: String,
        awsConfig: AWSAuthConfiguration,
        cdkDirectory: String = CDKStackConfiguration.defaultCDKDirectory,
        stackName: String = CDKStackConfiguration.defaultStackName,
        cliService: CLIService
    ) {
        self.stackName = stackName
        self.cdkService = CDKService(
            cdkDirectory: "\(projectRoot)/\(cdkDirectory)",
            awsConfig: awsConfig,
            cliService: cliService
        )
        self.awsService = AWSCLIService(awsConfig: awsConfig, cliService: cliService)
    }

    // MARK: - State Observation

    /// Stream of state changes. Immediately yields current state upon subscription.
    /// If state is `.unknown`, automatically triggers a refresh.
    public func states() -> AsyncStream<State> {
        // Auto-refresh on first observation if state is unknown
        if state == .unknown {
            Task { await refresh() }
        }

        return AsyncStream { continuation in
            let id = UUID()
            self.continuations[id] = continuation
            continuation.yield(self.state)

            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func publish(_ newState: State) {
        state = newState
        for continuation in continuations.values {
            continuation.yield(newState)
        }
    }

    // MARK: - Public Operations

    /// Refresh state from AWS
    public func refresh() async {
        guard !state.isBusy else { return }

        publish(.loading)

        do {
            let newState = try await queryCurrentState()
            publish(newState)

            if newState.isBusy {
                await monitorExistingOperation()
            }
        } catch CDKInfrastructureError.credentialExpired(let message) {
            publish(.credentialExpired(message: message))
        } catch {
            publish(.failed(reason: error.localizedDescription))
        }
    }

    /// Deploy infrastructure with specified configuration
    public func deploy(withPostgres: Bool, withNATGateway: Bool, output: CLIOutputStream? = nil) async {
        guard state.canDeploy else { return }

        let operationName = withPostgres ? "Deploying with Database" : "Deploying"
        let startTime = Date()
        publish(.deploying(operation: operationName, progress: CDKDeploymentProgress(), startTime: startTime))

        do {
            try await build(output: output)

            await executeDeployWithProgress(
                withPostgres: withPostgres,
                withNATGateway: withNATGateway,
                output: output,
                startTime: startTime
            )

            let finalState = try await queryCurrentState()
            publish(finalState)
        } catch {
            publish(.failed(reason: error.localizedDescription))
        }
    }

    /// Update infrastructure maintaining current configuration
    public func updateInfrastructure(output: CLIOutputStream? = nil) async {
        let hasDatabase = state.configuration.hasDatabase
        let hasNATGateway = state.configuration.hasNATGateway

        await deploy(withPostgres: hasDatabase, withNATGateway: hasNATGateway, output: output)
    }

    /// Destroy infrastructure
    public func destroy(output: CLIOutputStream? = nil) async {
        guard state.canDestroy else { return }

        let startTime = Date()
        publish(.destroying(progress: CDKDeploymentProgress(), startTime: startTime))

        do {
            await executeDestroyWithProgress(output: output, startTime: startTime)

            let finalState = try await queryCurrentState()
            publish(finalState)
        } catch {
            publish(.failed(reason: error.localizedDescription))
        }
    }

    // MARK: - Query Operations (Internal)

    private func getStackStatus() async throws -> String {
        try await awsService.getStackStatus(name: stackName)
    }

    private func getStackOutputs() async throws -> [String: String] {
        try await awsService.getStackOutputs(name: stackName)
    }

    private func queryConfiguration() async throws -> CDKInfrastructureConfiguration {
        let resources = try await awsService.describeStackResources(name: stackName)

        return CDKInfrastructureConfiguration(
            hasDatabase: resources.contains {
                $0.logicalResourceId.contains("Database") &&
                $0.resourceType.contains("RDS")
            },
            hasNATGateway: resources.contains {
                $0.resourceType == "AWS::EC2::NatGateway"
            },
            hasVPC: resources.contains {
                $0.resourceType == "AWS::EC2::VPC"
            }
        )
    }

    private func getStackEvents(limit: Int = 50) async throws -> [CloudFormationStackEvent] {
        try await awsService.getStackEvents(name: stackName, limit: limit)
    }

    /// Get the start time of the current operation from CloudFormation events
    /// Returns the earliest IN_PROGRESS timestamp for the stack resource itself
    private func getOperationStartTime() async -> Date? {
        guard let events = try? await getStackEvents() else { return nil }

        // Find the earliest IN_PROGRESS event for the stack itself (not individual resources)
        // The stack's own status change marks the operation start
        return events
            .filter { $0.logicalResourceId == stackName && $0.resourceStatus.contains("IN_PROGRESS") }
            .map { $0.timestamp }
            .min()
    }

    // MARK: - CDK Operations (Internal)

    private func build(output: CLIOutputStream? = nil) async throws {
        try await cdkService.build(output: output)
    }

    private func executeDeploy(
        withPostgres: Bool,
        withNATGateway: Bool,
        output: CLIOutputStream? = nil
    ) async throws {
        let options = CDKService.DeployOptions(
            skipPostgres: !withPostgres,
            skipNATGateway: !withNATGateway,
            requireApproval: false
        )
        try await cdkService.deploy(options: options, output: output)
    }

    private func executeDestroy(output: CLIOutputStream? = nil) async throws {
        try await cdkService.destroy(force: true, output: output)
    }

    // MARK: - State Query

    private func queryCurrentState() async throws -> State {
        do {
            let stackStatus = try await getStackStatus()

            switch stackStatus {
            case CloudFormationStackStatusValues.createComplete,
                 CloudFormationStackStatusValues.updateComplete:
                let configuration = try await queryConfiguration()
                let outputs = CDKStackOutputs.from(try await getStackOutputs())
                return .deployed(configuration: configuration, outputs: outputs)

            case CloudFormationStackStatusValues.createInProgress,
                 CloudFormationStackStatusValues.updateInProgress,
                 CloudFormationStackStatusValues.updateCompleteCleanupInProgress:
                let startTime = await getOperationStartTime() ?? Date()
                return .deploying(operation: "Updating", progress: CDKDeploymentProgress(), startTime: startTime)

            case CloudFormationStackStatusValues.deleteInProgress:
                let startTime = await getOperationStartTime() ?? Date()
                return .destroying(progress: CDKDeploymentProgress(), startTime: startTime)

            case CloudFormationStackStatusValues.createFailed,
                 CloudFormationStackStatusValues.updateFailed,
                 CloudFormationStackStatusValues.rollbackComplete,
                 CloudFormationStackStatusValues.rollbackFailed,
                 CloudFormationStackStatusValues.deleteFailed:
                return .failed(reason: stackStatus)

            default:
                let configuration = try await queryConfiguration()
                let outputs = CDKStackOutputs.from(try await getStackOutputs())
                return .deployed(configuration: configuration, outputs: outputs)
            }
        } catch {
            let errorMessage = error.localizedDescription

            if CDKInfrastructureError.isCredentialError(errorMessage) {
                throw CDKInfrastructureError.credentialExpired(message: errorMessage)
            } else if CDKInfrastructureError.isStackNotFoundError(errorMessage) {
                return .notDeployed
            } else {
                throw CDKInfrastructureError.unknown(message: errorMessage)
            }
        }
    }

    // MARK: - Progress Tracking

    private func executeDeployWithProgress(
        withPostgres: Bool,
        withNATGateway: Bool,
        output: CLIOutputStream?,
        startTime: Date
    ) async {
        let parser = CDKOutputParser()
        let accumulator = CDKProgressAccumulator()

        let parsingTask: Task<Void, Never>?
        if let output = output {
            parsingTask = Task {
                let stream = await output.makeStream()
                for await item in stream {
                    guard !Task.isCancelled else { break }

                    let text: String
                    switch item {
                    case .stdout(_, let t), .stderr(_, let t):
                        text = t
                    default:
                        continue
                    }

                    for line in text.components(separatedBy: .newlines) {
                        if let event = parser.parse(line) {
                            accumulator.update(with: event)
                            let progress = accumulator.snapshot().toDeploymentProgress()
                            self.publish(.deploying(operation: "Deploying", progress: progress, startTime: startTime))
                        }
                    }
                }
            }
        } else {
            parsingTask = nil
        }

        do {
            try await executeDeploy(withPostgres: withPostgres, withNATGateway: withNATGateway, output: output)
        } catch {
            parsingTask?.cancel()
            publish(.failed(reason: error.localizedDescription))
            return
        }

        parsingTask?.cancel()
    }

    private func executeDestroyWithProgress(output: CLIOutputStream?, startTime: Date) async {
        let parser = CDKOutputParser()
        let accumulator = CDKProgressAccumulator()

        let parsingTask: Task<Void, Never>?
        if let output = output {
            parsingTask = Task {
                let stream = await output.makeStream()
                for await item in stream {
                    guard !Task.isCancelled else { break }

                    let text: String
                    switch item {
                    case .stdout(_, let t), .stderr(_, let t):
                        text = t
                    default:
                        continue
                    }

                    for line in text.components(separatedBy: .newlines) {
                        if let event = parser.parse(line) {
                            accumulator.update(with: event)
                            let progress = accumulator.snapshot().toDeploymentProgress()
                            self.publish(.destroying(progress: progress, startTime: startTime))
                        }
                    }
                }
            }
        } else {
            parsingTask = nil
        }

        do {
            try await executeDestroy(output: output)
        } catch {
            parsingTask?.cancel()
            publish(.failed(reason: error.localizedDescription))
            return
        }

        parsingTask?.cancel()
    }

    private func monitorExistingOperation() async {
        var pollCount = 0
        let startTime = state.operationStartTime ?? Date()

        while !Task.isCancelled {
            pollCount += 1

            do {
                let events = try await getStackEvents()
                let progress = CDKDeploymentProgress.from(
                    events: events,
                    since: nil,
                    pollCount: pollCount
                )

                if case .deploying(let op, _, _) = state {
                    publish(.deploying(operation: op, progress: progress, startTime: startTime))
                } else if case .destroying = state {
                    publish(.destroying(progress: progress, startTime: startTime))
                }

                let status = try await getStackStatus()

                if !CloudFormationStackStatusValues.isInProgress(status) {
                    let finalState = try await queryCurrentState()
                    publish(finalState)
                    return
                }
            } catch {
                // Continue polling
            }

            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                break
            }
        }
    }
}
