import CLIKit
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
        cdkDirectory: String = "cdk",
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

    // MARK: - High-Level Status Snapshot

    /// Get complete infrastructure status snapshot
    /// - Parameter stackName: Name of the stack
    /// - Returns: Complete status snapshot with state, configuration, and outputs
    /// - Throws: CDKInfrastructureError for credential issues
    public func getFullStatus(stackName: String) async throws -> CDKInfrastructureStatusSnapshot {
        do {
            let stackStatus = try await getStackStatus(stackName: stackName)

            switch stackStatus {
            case CloudFormationStackStatusValues.createComplete,
                 CloudFormationStackStatusValues.updateComplete:
                let config = try await queryConfiguration(stackName: stackName)
                let outputs = try await getStackOutputs(stackName: stackName)

                return CDKInfrastructureStatusSnapshot(
                    state: .deployed,
                    configuration: config,
                    outputs: CDKStackOutputs.from(outputs)
                )

            case CloudFormationStackStatusValues.createInProgress,
                 CloudFormationStackStatusValues.updateInProgress,
                 CloudFormationStackStatusValues.updateCompleteCleanupInProgress:
                return CDKInfrastructureStatusSnapshot(state: .deploying(operation: "Updating"))

            case CloudFormationStackStatusValues.deleteInProgress:
                return CDKInfrastructureStatusSnapshot(state: .destroying)

            case CloudFormationStackStatusValues.createFailed,
                 CloudFormationStackStatusValues.updateFailed,
                 CloudFormationStackStatusValues.rollbackComplete,
                 CloudFormationStackStatusValues.rollbackFailed,
                 CloudFormationStackStatusValues.deleteFailed:
                return CDKInfrastructureStatusSnapshot(state: .failed(reason: stackStatus))

            default:
                return CDKInfrastructureStatusSnapshot(state: .deployed)
            }
        } catch {
            let errorMessage = error.localizedDescription

            if CDKInfrastructureError.isCredentialError(errorMessage) {
                throw CDKInfrastructureError.credentialExpired(message: errorMessage)
            } else {
                return CDKInfrastructureStatusSnapshot(state: .notDeployed)
            }
        }
    }

    // MARK: - Progress Streaming Operations

    /// Deploy CDK stack with progress streaming
    /// - Parameters:
    ///   - stackName: Name of the stack to monitor
    ///   - withPostgres: Include PostgreSQL database
    ///   - withNATGateway: Include NAT Gateway
    ///   - output: Optional stream to receive CDK output
    /// - Returns: AsyncStream yielding progress snapshots until deployment completes
    public nonisolated func deployWithProgress(
        stackName: String,
        withPostgres: Bool,
        withNATGateway: Bool,
        output: CLIOutputStream? = nil
    ) -> AsyncThrowingStream<CDKDeploymentProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let startTime = Date()

                do {
                    try await self.build(output: output)
                } catch {
                    continuation.finish(throwing: CDKInfrastructureError.buildFailed(reason: error.localizedDescription))
                    return
                }

                let deployTask = Task {
                    try await self.deploy(withPostgres: withPostgres, withNATGateway: withNATGateway, output: output)
                }

                let pollingTask = Task {
                    var pollCount = 0
                    while !Task.isCancelled {
                        pollCount += 1

                        do {
                            let events = try await self.getStackEvents(stackName: stackName)
                            let progress = CDKDeploymentProgress.from(
                                events: events,
                                since: startTime,
                                pollCount: pollCount
                            )
                            continuation.yield(progress)
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
                }

                do {
                    try await deployTask.value
                    pollingTask.cancel()

                    let finalEvents = try await self.getStackEvents(stackName: stackName)
                    let finalProgress = CDKDeploymentProgress.from(
                        events: finalEvents,
                        since: startTime,
                        pollCount: 0,
                        isComplete: true
                    )
                    continuation.yield(finalProgress)
                    continuation.finish()
                } catch {
                    pollingTask.cancel()
                    continuation.finish(throwing: CDKInfrastructureError.deploymentFailed(reason: error.localizedDescription))
                }
            }
        }
    }

    /// Destroy CDK stack with progress streaming
    /// - Parameters:
    ///   - stackName: Name of the stack to monitor
    ///   - output: Optional stream to receive CDK output
    /// - Returns: AsyncStream yielding progress snapshots until destroy completes
    public nonisolated func destroyWithProgress(
        stackName: String,
        output: CLIOutputStream? = nil
    ) -> AsyncThrowingStream<CDKDeploymentProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let startTime = Date()

                let destroyTask = Task {
                    try await self.destroy(output: output)
                }

                let pollingTask = Task {
                    var pollCount = 0
                    while !Task.isCancelled {
                        pollCount += 1

                        do {
                            let events = try await self.getStackEvents(stackName: stackName)
                            let progress = CDKDeploymentProgress.from(
                                events: events,
                                since: startTime,
                                pollCount: pollCount
                            )
                            continuation.yield(progress)
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
                }

                do {
                    try await destroyTask.value
                    pollingTask.cancel()

                    let finalProgress = CDKDeploymentProgress(pollCount: 0, isComplete: true)
                    continuation.yield(finalProgress)
                    continuation.finish()
                } catch {
                    pollingTask.cancel()
                    continuation.finish(throwing: CDKInfrastructureError.deploymentFailed(reason: error.localizedDescription))
                }
            }
        }
    }

    /// Monitor an existing in-progress operation
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
}

// MARK: - Data Types

/// Detected infrastructure configuration from CloudFormation
public struct CDKInfrastructureConfiguration: Equatable, Sendable {
    public let hasDatabase: Bool
    public let hasNATGateway: Bool
    public let hasVPC: Bool

    public init(hasDatabase: Bool = false, hasNATGateway: Bool = false, hasVPC: Bool = false) {
        self.hasDatabase = hasDatabase
        self.hasNATGateway = hasNATGateway
        self.hasVPC = hasVPC
    }
}

/// Parsed stack output values
public struct CDKStackOutputs: Equatable, Sendable {
    public let apiGatewayUrl: String?
    public let lambdaFunctionName: String?
    public let bucketName: String?
    public let allOutputs: [String: String]

    public init(
        apiGatewayUrl: String? = nil,
        lambdaFunctionName: String? = nil,
        bucketName: String? = nil,
        allOutputs: [String: String] = [:]
    ) {
        self.apiGatewayUrl = apiGatewayUrl
        self.lambdaFunctionName = lambdaFunctionName
        self.bucketName = bucketName
        self.allOutputs = allOutputs
    }

    public static func from(_ outputs: [String: String]) -> CDKStackOutputs {
        CDKStackOutputs(
            apiGatewayUrl: outputs["ApiGatewayUrl"],
            lambdaFunctionName: outputs["LambdaFunctionName"],
            bucketName: outputs["BucketName"],
            allOutputs: outputs
        )
    }
}

/// CloudFormation stack status values
/// See: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-describing-stacks.html
public enum CloudFormationStackStatusValues {
    // Successful states
    public static let createComplete = "CREATE_COMPLETE"
    public static let updateComplete = "UPDATE_COMPLETE"

    // In-progress states
    public static let createInProgress = "CREATE_IN_PROGRESS"
    public static let updateInProgress = "UPDATE_IN_PROGRESS"
    public static let updateCompleteCleanupInProgress = "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS"
    public static let deleteInProgress = "DELETE_IN_PROGRESS"

    // Failed states
    public static let createFailed = "CREATE_FAILED"
    public static let updateFailed = "UPDATE_FAILED"
    public static let rollbackComplete = "ROLLBACK_COMPLETE"
    public static let rollbackFailed = "ROLLBACK_FAILED"
    public static let deleteFailed = "DELETE_FAILED"

    /// Check if status indicates the stack is successfully deployed
    public static func isDeployed(_ status: String) -> Bool {
        status == createComplete || status == updateComplete
    }

    /// Check if status indicates an in-progress operation
    public static func isInProgress(_ status: String) -> Bool {
        switch status {
        case createInProgress, updateInProgress, updateCompleteCleanupInProgress, deleteInProgress:
            return true
        default:
            return false
        }
    }

    /// Check if status indicates a failed state
    public static func isFailed(_ status: String) -> Bool {
        switch status {
        case createFailed, updateFailed, rollbackComplete, rollbackFailed, deleteFailed:
            return true
        default:
            return false
        }
    }

    /// Check if status indicates a delete operation in progress
    public static func isDeleting(_ status: String) -> Bool {
        status == deleteInProgress
    }
}

/// Typed errors for CDK Infrastructure operations
public enum CDKInfrastructureError: Error, Equatable, Sendable {
    case credentialExpired(message: String)
    case stackNotFound(stackName: String)
    case deploymentFailed(reason: String)
    case buildFailed(reason: String)
    case operationInProgress(operation: String)
    case unknown(message: String)

    public var localizedDescription: String {
        switch self {
        case .credentialExpired(let message):
            return "AWS credentials expired: \(message)"
        case .stackNotFound(let stackName):
            return "Stack not found: \(stackName)"
        case .deploymentFailed(let reason):
            return "Deployment failed: \(reason)"
        case .buildFailed(let reason):
            return "Build failed: \(reason)"
        case .operationInProgress(let operation):
            return "Operation in progress: \(operation)"
        case .unknown(let message):
            return message
        }
    }

    /// Check if an error message indicates AWS credential issues
    public static func isCredentialError(_ error: String) -> Bool {
        let credentialPatterns = [
            "credentials missing",
            "credential_process",
            "Error getting temporary credentials",
            "ExpiredToken",
            "InvalidClientTokenId",
            "AccessDenied",
            "AuthFailure",
            "security token included in the request is invalid",
            "could not be found"
        ]
        return credentialPatterns.contains { error.localizedCaseInsensitiveContains($0) }
    }
}

/// Complete status snapshot for CDK infrastructure
public struct CDKInfrastructureStatusSnapshot: Sendable, Equatable {
    public enum StackState: Sendable, Equatable {
        case notDeployed
        case deployed
        case deploying(operation: String)
        case destroying
        case failed(reason: String)
    }

    public let state: StackState
    public let configuration: CDKInfrastructureConfiguration
    public let outputs: CDKStackOutputs

    public init(
        state: StackState,
        configuration: CDKInfrastructureConfiguration = CDKInfrastructureConfiguration(),
        outputs: CDKStackOutputs = CDKStackOutputs()
    ) {
        self.state = state
        self.configuration = configuration
        self.outputs = outputs
    }
}

/// Progress snapshot during deployment/destroy operations
public struct CDKDeploymentProgress: Sendable, Equatable {
    public let resources: [ResourceProgressSnapshot]
    public let pollCount: Int
    public let isComplete: Bool

    public var completedCount: Int {
        resources.filter { $0.status.isComplete }.count
    }

    public var inProgressCount: Int {
        resources.filter { $0.status.isInProgress }.count
    }

    public var hasFailures: Bool {
        resources.contains { $0.status.isFailed }
    }

    public var hasPolled: Bool { pollCount > 0 }
    public var hasPolledEnough: Bool { pollCount >= 5 }

    public init(resources: [ResourceProgressSnapshot] = [], pollCount: Int = 0, isComplete: Bool = false) {
        self.resources = resources
        self.pollCount = pollCount
        self.isComplete = isComplete
    }

    /// Create progress snapshot from CloudFormation events
    public static func from(events: [CloudFormationStackEvent], since: Date?, pollCount: Int, isComplete: Bool = false) -> CDKDeploymentProgress {
        let relevantEvents = events.filter { event in
            guard let since = since else { return true }
            return event.timestamp >= since
        }

        var latestByResource: [String: CloudFormationStackEvent] = [:]
        for event in relevantEvents {
            if event.resourceType == "AWS::CloudFormation::Stack" { continue }

            if let existing = latestByResource[event.logicalResourceId] {
                if event.timestamp > existing.timestamp {
                    latestByResource[event.logicalResourceId] = event
                }
            } else {
                latestByResource[event.logicalResourceId] = event
            }
        }

        let resources = latestByResource.values
            .sorted { $0.timestamp > $1.timestamp }
            .map { ResourceProgressSnapshot(from: $0) }

        return CDKDeploymentProgress(resources: resources, pollCount: pollCount, isComplete: isComplete)
    }
}

/// Progress snapshot for a single resource
public struct ResourceProgressSnapshot: Sendable, Equatable, Identifiable {
    public let resourceId: String
    public let displayName: String
    public let resourceType: String
    public let status: ResourceStatusSnapshot
    public let statusReason: String?
    public let timestamp: Date

    public var id: String { resourceId }

    public init(from event: CloudFormationStackEvent) {
        self.resourceId = event.logicalResourceId
        self.displayName = event.displayName
        self.resourceType = event.displayType
        self.status = ResourceStatusSnapshot(from: event.resourceStatus)
        self.statusReason = event.resourceStatusReason
        self.timestamp = event.timestamp
    }
}

/// Status of a resource during deployment
public enum ResourceStatusSnapshot: Sendable, Equatable {
    case pending
    case inProgress
    case complete
    case failed(reason: String?)

    public var isInProgress: Bool {
        if case .inProgress = self { return true }
        return false
    }

    public var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    public init(from status: String) {
        if status.contains("COMPLETE") && !status.contains("CLEANUP") && !status.contains("ROLLBACK") {
            self = .complete
        } else if status.contains("IN_PROGRESS") {
            self = .inProgress
        } else if status.contains("FAILED") || status.contains("ROLLBACK") {
            self = .failed(reason: nil)
        } else {
            self = .pending
        }
    }
}
