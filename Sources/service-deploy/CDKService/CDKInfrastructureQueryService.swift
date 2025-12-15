import sdk_cli
import Foundation

/// Stateless service for CDK Infrastructure queries and operations
/// Provides methods for querying CloudFormation state and executing CDK commands
public actor CDKInfrastructureQueryService {
    private let cdkService: CDKService
    private let awsService: AWSCLIService

    // MARK: - Initialization

    public init(
        projectRoot: String,
        awsConfig: AWSAuthConfiguration,
        cdkDirectory: String = CDKStackConfiguration.defaultCDKDirectory,
        cliService: CLIService
    ) {
        self.cdkService = CDKService(
            cdkDirectory: "\(projectRoot)/\(cdkDirectory)",
            awsConfig: awsConfig,
            cliService: cliService
        )
        self.awsService = AWSCLIService(awsConfig: awsConfig, cliService: cliService)
    }

    // MARK: - Query Operations

    /// Get current CloudFormation stack status
    /// - Parameter stackName: Name of the stack
    /// - Returns: Status string (e.g., "CREATE_COMPLETE", "UPDATE_IN_PROGRESS")
    public func getStackStatus(stackName: String) async throws -> String {
        try await awsService.getStackStatus(name: stackName)
    }

    /// Get stack outputs from CloudFormation
    /// - Parameter stackName: Name of the stack
    /// - Returns: Dictionary of output key-value pairs
    public func getStackOutputs(stackName: String) async throws -> [String: String] {
        try await awsService.getStackOutputs(name: stackName)
    }

    /// Query current infrastructure configuration from CloudFormation resources
    /// - Parameter stackName: Name of the stack
    /// - Returns: Configuration indicating what's deployed
    public func queryConfiguration(stackName: String) async throws -> CDKInfrastructureConfiguration {
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

    /// Get stack events for deployment progress tracking
    /// - Parameters:
    ///   - stackName: Name of the stack
    ///   - limit: Maximum number of events to return
    /// - Returns: Array of stack events
    public func getStackEvents(stackName: String, limit: Int = 50) async throws -> [CloudFormationStackEvent] {
        try await awsService.getStackEvents(name: stackName, limit: limit)
    }

    // MARK: - CDK Operations

    /// Build CDK TypeScript
    /// - Parameter output: Optional stream to receive output
    public func build(output: CLIOutputStream? = nil) async throws {
        try await cdkService.build(output: output)
    }

    /// Deploy CDK stack
    /// - Parameters:
    ///   - withPostgres: Include PostgreSQL database
    ///   - withNATGateway: Include NAT Gateway
    ///   - output: Optional stream to receive output
    public func deploy(
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

    /// Destroy CDK stack
    /// - Parameter output: Optional stream to receive output
    public func destroy(output: CLIOutputStream? = nil) async throws {
        try await cdkService.destroy(force: true, output: output)
    }

    // MARK: - High-Level Status

    /// Get complete infrastructure status
    /// - Parameter stackName: Name of the stack
    /// - Returns: Complete status with state, configuration, and outputs
    /// - Throws: CDKInfrastructureError for credential issues or unexpected errors
    public func getFullStatus(stackName: String) async throws -> CDKInfrastructureStatus {
        var result = CDKInfrastructureStatus(stackName: stackName)

        do {
            let stackStatus = try await getStackStatus(stackName: stackName)

            switch stackStatus {
            case CloudFormationStackStatusValues.createComplete,
                 CloudFormationStackStatusValues.updateComplete:
                result.configuration = try await queryConfiguration(stackName: stackName)
                result.outputs = CDKStackOutputs.from(try await getStackOutputs(stackName: stackName))
                result.status = .deployed

            case CloudFormationStackStatusValues.createInProgress,
                 CloudFormationStackStatusValues.updateInProgress,
                 CloudFormationStackStatusValues.updateCompleteCleanupInProgress:
                result.status = .deploying(operation: "Updating")

            case CloudFormationStackStatusValues.deleteInProgress:
                result.status = .destroying

            case CloudFormationStackStatusValues.createFailed,
                 CloudFormationStackStatusValues.updateFailed,
                 CloudFormationStackStatusValues.rollbackComplete,
                 CloudFormationStackStatusValues.rollbackFailed,
                 CloudFormationStackStatusValues.deleteFailed:
                result.status = .failed(reason: stackStatus)

            default:
                result.status = .deployed
            }
        } catch {
            let errorMessage = error.localizedDescription

            if CDKInfrastructureError.isCredentialError(errorMessage) {
                throw CDKInfrastructureError.credentialExpired(message: errorMessage)
            } else if CDKInfrastructureError.isStackNotFoundError(errorMessage) {
                result.status = .notDeployed
            } else {
                throw CDKInfrastructureError.unknown(message: errorMessage)
            }
        }

        return result
    }

    // MARK: - Progress Streaming Operations

    /// Deploy CDK stack with progress streaming
    /// Progress is extracted by parsing CDK CLI output in real-time
    /// - Parameters:
    ///   - stackName: Name of the stack to monitor (unused, kept for API compatibility)
    ///   - withPostgres: Include PostgreSQL database
    ///   - withNATGateway: Include NAT Gateway
    ///   - output: Stream to receive CDK output (required for progress parsing)
    /// - Returns: AsyncStream yielding progress snapshots until deployment completes
    public nonisolated func deployWithProgress(
        stackName: String,
        withPostgres: Bool,
        withNATGateway: Bool,
        output: CLIOutputStream? = nil
    ) -> AsyncThrowingStream<CDKDeploymentProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Build first (no progress parsing needed)
                do {
                    try await self.build(output: output)
                } catch {
                    continuation.finish(throwing: CDKInfrastructureError.buildFailed(reason: error.localizedDescription))
                    return
                }

                // Deploy with progress parsing
                await self.executeWithOutputParsing(
                    output: output,
                    continuation: continuation
                ) {
                    try await self.deploy(withPostgres: withPostgres, withNATGateway: withNATGateway, output: output)
                }
            }
        }
    }

    /// Destroy CDK stack with progress streaming
    /// Progress is extracted by parsing CDK CLI output in real-time
    /// - Parameters:
    ///   - stackName: Name of the stack to monitor (unused, kept for API compatibility)
    ///   - output: Stream to receive CDK output (required for progress parsing)
    /// - Returns: AsyncStream yielding progress snapshots until destroy completes
    public nonisolated func destroyWithProgress(
        stackName: String,
        output: CLIOutputStream? = nil
    ) -> AsyncThrowingStream<CDKDeploymentProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.executeWithOutputParsing(
                    output: output,
                    continuation: continuation
                ) {
                    try await self.destroy(output: output)
                }
            }
        }
    }

    /// Monitor an existing in-progress operation
    /// Note: This still uses polling since we don't have access to CDK output stream
    /// - Parameter stackName: Name of the stack to monitor
    /// - Returns: AsyncStream yielding progress snapshots until operation completes
    public nonisolated func monitorOperation(stackName: String) -> AsyncThrowingStream<CDKDeploymentProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var pollCount = 0

                while !Task.isCancelled {
                    pollCount += 1

                    do {
                        let events = try await self.getStackEvents(stackName: stackName)
                        let progress = CDKDeploymentProgress.from(
                            events: events,
                            since: nil,
                            pollCount: pollCount
                        )
                        continuation.yield(progress)

                        let status = try await self.getStackStatus(stackName: stackName)

                        if !CloudFormationStackStatusValues.isInProgress(status) {
                            let finalProgress = CDKDeploymentProgress.from(
                                events: events,
                                since: nil,
                                pollCount: pollCount,
                                isComplete: true
                            )
                            continuation.yield(finalProgress)
                            continuation.finish()
                            return
                        }
                    } catch {
                        let progress = CDKDeploymentProgress(pollCount: pollCount)
                        continuation.yield(progress)
                    }

                    do {
                        try await Task.sleep(for: .seconds(2))
                    } catch {
                        break
                    }
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Private Helpers

    /// Execute an operation while parsing CDK output for progress updates
    /// - Parameters:
    ///   - output: The output stream to parse (if nil, only yields completion)
    ///   - continuation: Stream continuation to yield progress updates
    ///   - operation: The async operation to execute
    private func executeWithOutputParsing(
        output: CLIOutputStream?,
        continuation: AsyncThrowingStream<CDKDeploymentProgress, Error>.Continuation,
        operation: @escaping @Sendable () async throws -> Void
    ) async {
        let parser = CDKOutputParser()
        let accumulator = CDKProgressAccumulator()

        // Start parsing task if we have an output stream
        let parsingTask: Task<Void, Never>?
        if let output = output {
            parsingTask = Task {
                let stream = await output.makeStream()
                for await item in stream {
                    guard !Task.isCancelled else { break }

                    // Extract text from stdout
                    let text: String
                    switch item {
                    case .stdout(_, let t), .stderr(_, let t):
                        text = t
                    default:
                        continue
                    }

                    // Parse each line
                    for line in text.components(separatedBy: .newlines) {
                        if let event = parser.parse(line) {
                            accumulator.update(with: event)
                            let progress = accumulator.snapshot().toDeploymentProgress()
                            continuation.yield(progress)
                        }
                    }
                }
            }
        } else {
            parsingTask = nil
        }

        // Execute the operation
        do {
            try await operation()

            // Cancel parsing and yield final progress
            parsingTask?.cancel()
            let finalProgress = accumulator.snapshot().toDeploymentProgress(isComplete: true)
            continuation.yield(finalProgress)
            continuation.finish()
        } catch {
            parsingTask?.cancel()
            continuation.finish(throwing: CDKInfrastructureError.deploymentFailed(reason: error.localizedDescription))
        }
    }
}
