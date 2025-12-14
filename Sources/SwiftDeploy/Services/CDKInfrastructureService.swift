import CLIKit
import Foundation
import Observation

/// CloudFormation stack status values
/// See: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-describing-stacks.html
public enum CloudFormationStackStatus {
    // Successful states
    static let createComplete = "CREATE_COMPLETE"
    static let updateComplete = "UPDATE_COMPLETE"

    // In-progress states
    static let createInProgress = "CREATE_IN_PROGRESS"
    static let updateInProgress = "UPDATE_IN_PROGRESS"
    static let updateCompleteCleanupInProgress = "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS"
    static let deleteInProgress = "DELETE_IN_PROGRESS"

    // Failed states
    static let createFailed = "CREATE_FAILED"
    static let updateFailed = "UPDATE_FAILED"
    static let rollbackComplete = "ROLLBACK_COMPLETE"
    static let rollbackFailed = "ROLLBACK_FAILED"
    static let deleteFailed = "DELETE_FAILED"
}

/// State for CDK Infrastructure tracking
public struct CDKInfrastructureStatus: Equatable {
    public enum StackStatus: Equatable {
        case unknown
        case loading
        case notDeployed
        case deployed
        case deploying(operation: String)
        case destroying
        case failed(reason: String)

        public var isDeploying: Bool {
            if case .deploying = self { return true }
            return false
        }

        public var isDestroying: Bool {
            if case .destroying = self { return true }
            return false
        }

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
    }

    /// Detected infrastructure configuration
    public struct Configuration: Equatable {
        public let hasDatabase: Bool
        public let hasNATGateway: Bool
        public let hasVPC: Bool

        public init(hasDatabase: Bool = false, hasNATGateway: Bool = false, hasVPC: Bool = false) {
            self.hasDatabase = hasDatabase
            self.hasNATGateway = hasNATGateway
            self.hasVPC = hasVPC
        }
    }

    /// Stack output values
    public struct StackOutputs: Equatable {
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

        public static func from(_ outputs: [String: String]) -> StackOutputs {
            StackOutputs(
                apiGatewayUrl: outputs["ApiGatewayUrl"],
                lambdaFunctionName: outputs["LambdaFunctionName"],
                bucketName: outputs["BucketName"],
                allOutputs: outputs
            )
        }
    }

    public var status: StackStatus = .unknown
    public var configuration: Configuration = Configuration()
    public var outputs: StackOutputs = StackOutputs()
    public var stackName: String = "SwiftLambdaSampleStack"
    public var deployStartTime: Date?

    /// Deployment progress - aggregated resource states during deploy/destroy
    public var deploymentProgress: DeploymentProgress = DeploymentProgress()

    public init() {}

    /// Aggregated deployment progress for UI display
    public struct DeploymentProgress: Equatable {
        /// Resources being tracked during deployment
        public var resources: [ResourceProgress] = []

        /// Total resources expected (if known)
        public var totalExpected: Int?

        /// Number of resources completed
        public var completedCount: Int {
            resources.filter { $0.status.isComplete }.count
        }

        /// Number of resources in progress
        public var inProgressCount: Int {
            resources.filter { $0.status.isInProgress }.count
        }

        /// Whether there are any failures
        public var hasFailures: Bool {
            resources.contains { $0.status.isFailed }
        }

        public init() {}

        /// Number of times we've polled
        public var pollCount: Int = 0

        /// Whether we've polled at least once
        public var hasPolled: Bool { pollCount > 0 }

        /// Whether we've polled enough times to conclude no changes (e.g., 5+ polls = 10+ seconds)
        public var hasPolledEnough: Bool { pollCount >= 5 }

        /// Update with new events (aggregates by resource)
        public mutating func update(from events: [CloudFormationStackEvent], since: Date?) {
            pollCount += 1

            // Filter to events since deployment started
            let relevantEvents = events.filter { event in
                guard let since = since else { return true }
                return event.timestamp >= since
            }

            // Group events by logical resource ID, keeping latest event per resource
            var latestByResource: [String: CloudFormationStackEvent] = [:]
            for event in relevantEvents {
                // Skip the stack itself
                if event.resourceType == "AWS::CloudFormation::Stack" { continue }

                if let existing = latestByResource[event.logicalResourceId] {
                    if event.timestamp > existing.timestamp {
                        latestByResource[event.logicalResourceId] = event
                    }
                } else {
                    latestByResource[event.logicalResourceId] = event
                }
            }

            // Convert to ResourceProgress sorted by timestamp (most recent first)
            resources = latestByResource.values
                .sorted { $0.timestamp > $1.timestamp }
                .map { ResourceProgress(from: $0) }
        }

        public mutating func clear() {
            resources = []
            totalExpected = nil
            pollCount = 0
        }
    }

    /// Progress for a single resource
    public struct ResourceProgress: Equatable, Identifiable {
        public let resourceId: String
        public let displayName: String
        public let resourceType: String
        public let status: ResourceStatus
        public let statusReason: String?
        public let timestamp: Date

        public var id: String { resourceId }

        public init(from event: CloudFormationStackEvent) {
            self.resourceId = event.logicalResourceId
            self.displayName = event.displayName
            self.resourceType = event.displayType
            self.status = ResourceStatus(from: event.resourceStatus)
            self.statusReason = event.resourceStatusReason
            self.timestamp = event.timestamp
        }
    }

    /// Status of a resource during deployment
    public enum ResourceStatus: Equatable {
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
}

/// Service for CDK Infrastructure operations with UI state management
@MainActor
@Observable
public final class CDKInfrastructureService {
    // MARK: - State (source of truth)

    public private(set) var infrastructureStatus = CDKInfrastructureStatus()

    // MARK: - Private Services

    private let cdkService: CDKService
    private let awsService: AWSCLIService
    private let projectRoot: String

    // MARK: - Init

    public init(projectRoot: String, awsConfig: AWSAuthConfiguration, cdkDirectory: String = "cdk", cliService: CLIService) {
        self.projectRoot = projectRoot
        self.cdkService = CDKService(
            cdkDirectory: "\(projectRoot)/\(cdkDirectory)",
            awsConfig: awsConfig,
            cliService: cliService
        )
        self.awsService = AWSCLIService(awsConfig: awsConfig, cliService: cliService)
    }

    // MARK: - UI State Operations

    /// Refresh infrastructure status including stack state, configuration, and outputs.
    /// - Parameter force: If true, bypasses the isBusy check (used after deploy/destroy completes)
    public func refreshStatus(force: Bool = false) async {
        // Don't refresh if we're in the middle of an operation (unless forced)
        guard force || !infrastructureStatus.status.isBusy else { return }

        infrastructureStatus.status = .loading

        do {
            // Check if stack exists and get its status
            let stackStatus = try await awsService.getStackStatus(name: infrastructureStatus.stackName)

            switch stackStatus {
            case CloudFormationStackStatus.createComplete,
                 CloudFormationStackStatus.updateComplete:
                // Stack is deployed - get configuration and outputs
                let config = try await queryConfiguration()
                let outputs = try await awsService.getStackOutputs(name: infrastructureStatus.stackName)

                infrastructureStatus.configuration = config
                infrastructureStatus.outputs = CDKInfrastructureStatus.StackOutputs.from(outputs)
                infrastructureStatus.status = .deployed

            case CloudFormationStackStatus.createInProgress,
                 CloudFormationStackStatus.updateInProgress,
                 CloudFormationStackStatus.updateCompleteCleanupInProgress:
                infrastructureStatus.status = .deploying(operation: "Updating")
                // Start monitoring the in-progress operation
                Task {
                    await monitorExistingOperation()
                }

            case CloudFormationStackStatus.deleteInProgress:
                infrastructureStatus.status = .destroying
                // Start monitoring the in-progress operation
                Task {
                    await monitorExistingOperation()
                }

            case CloudFormationStackStatus.createFailed,
                 CloudFormationStackStatus.updateFailed,
                 CloudFormationStackStatus.rollbackComplete,
                 CloudFormationStackStatus.rollbackFailed,
                 CloudFormationStackStatus.deleteFailed:
                infrastructureStatus.status = .failed(reason: stackStatus)

            default:
                infrastructureStatus.status = .deployed
            }
        } catch {
            let errorMessage = error.localizedDescription

            // Check if this is a credential error vs stack not found
            if Self.isCredentialError(errorMessage) {
                infrastructureStatus.status = .failed(reason: errorMessage)
            } else {
                // Stack doesn't exist or other non-credential error
                infrastructureStatus.status = .notDeployed
                infrastructureStatus.configuration = CDKInfrastructureStatus.Configuration()
                infrastructureStatus.outputs = CDKInfrastructureStatus.StackOutputs()
            }
        }
    }

    /// Check if an error message indicates AWS credential issues
    private static func isCredentialError(_ error: String) -> Bool {
        let credentialPatterns = [
            "credentials missing",
            "credential_process",
            "Error getting temporary credentials",
            "ExpiredToken",
            "InvalidClientTokenId",
            "AccessDenied",
            "AuthFailure",
            "security token included in the request is invalid",
            "could not be found"  // Profile not found
        ]
        return credentialPatterns.contains { error.localizedCaseInsensitiveContains($0) }
    }

    /// Deploy infrastructure with specified configuration
    /// - Parameters:
    ///   - withPostgres: Include PostgreSQL database
    ///   - withNATGateway: Include NAT Gateway
    ///   - output: Optional client-owned stream to receive output (in addition to global stream)
    public func deploy(withPostgres: Bool, withNATGateway: Bool, output: CLIOutputStream? = nil) async throws {
        infrastructureStatus.deployStartTime = Date()
        infrastructureStatus.deploymentProgress.clear()
        infrastructureStatus.status = .deploying(operation: withPostgres ? "Deploying with Database" : "Deploying")

        do {
            // Build CDK first
            try await cdkService.build(output: output)

            // Deploy with options
            let options = CDKService.DeployOptions(
                skipPostgres: !withPostgres,
                skipNATGateway: !withNATGateway,
                requireApproval: false
            )

            // Run CDK deploy in background while polling for progress
            try await runDeployWithProgressPolling {
                try await self.cdkService.deploy(options: options, output: output)
            }

            // Refresh to get final state (force: true to bypass isBusy check since status is still .deploying)
            await refreshStatus(force: true)
        } catch {
            infrastructureStatus.status = .failed(reason: error.localizedDescription)
            infrastructureStatus.deployStartTime = nil
            infrastructureStatus.deploymentProgress.clear()
            throw error
        }
    }

    /// Update infrastructure maintaining current configuration
    /// - Parameter output: Optional client-owned stream to receive output (in addition to global stream)
    public func updateInfrastructure(output: CLIOutputStream? = nil) async throws {
        infrastructureStatus.deployStartTime = Date()
        infrastructureStatus.deploymentProgress.clear()
        infrastructureStatus.status = .deploying(operation: "Updating")

        do {
            // Build CDK first
            try await cdkService.build(output: output)

            // Deploy maintaining current config
            let options = CDKService.DeployOptions(
                skipPostgres: !infrastructureStatus.configuration.hasDatabase,
                skipNATGateway: !infrastructureStatus.configuration.hasNATGateway,
                requireApproval: false
            )

            // Run CDK deploy in background while polling for progress
            try await runDeployWithProgressPolling {
                try await self.cdkService.deploy(options: options, output: output)
            }

            // Refresh to get final state (force: true to bypass isBusy check since status is still .deploying)
            await refreshStatus(force: true)
        } catch {
            infrastructureStatus.status = .failed(reason: error.localizedDescription)
            infrastructureStatus.deployStartTime = nil
            infrastructureStatus.deploymentProgress.clear()
            throw error
        }
    }

    /// Run a CDK operation while polling for CloudFormation progress
    private func runDeployWithProgressPolling(_ cdkOperation: @escaping @Sendable () async throws -> Void) async throws {
        let stackName = infrastructureStatus.stackName
        let startTime = infrastructureStatus.deployStartTime

        // Start polling in a DETACHED task to escape MainActor
        // This allows polling to run concurrently with the CDK operation
        let pollingTask = Task.detached { [awsService] in
            await self.pollProgressUntilCancelled(
                stackName: stackName,
                startTime: startTime,
                awsService: awsService
            )
        }

        // Run CDK operation in a DETACHED task too!
        // This is critical because CLIService.execute uses synchronous process.waitUntilExit()
        // which would block MainActor and prevent polling updates from being applied
        let cdkTask = Task.detached {
            try await cdkOperation()
        }

        // Wait for CDK to complete
        do {
            try await cdkTask.value
        } catch {
            pollingTask.cancel()
            throw error
        }

        // Stop polling
        pollingTask.cancel()

        // Do one final poll to get completion status
        try? await updateProgressOnce()

        infrastructureStatus.deployStartTime = nil
        infrastructureStatus.deploymentProgress.clear()
    }

    /// Poll progress continuously until cancelled (runs off MainActor)
    private nonisolated func pollProgressUntilCancelled(
        stackName: String,
        startTime: Date?,
        awsService: AWSCLIService
    ) async {
        let pollInterval: Duration = .seconds(2)

        while !Task.isCancelled {
            do {
                let events = try await awsService.getStackEvents(name: stackName)

                // Update UI on MainActor
                await MainActor.run {
                    self.infrastructureStatus.deploymentProgress.update(
                        from: events,
                        since: startTime
                    )
                }
            } catch {
                // Stack might not exist yet (during initial create) - still count as a poll
                await MainActor.run {
                    self.infrastructureStatus.deploymentProgress.pollCount += 1
                }
            }

            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                // Task was cancelled during sleep
                break
            }
        }
    }

    /// Single progress update (runs on MainActor)
    private func updateProgressOnce() async throws {
        let events = try await awsService.getStackEvents(name: infrastructureStatus.stackName)
        infrastructureStatus.deploymentProgress.update(
            from: events,
            since: infrastructureStatus.deployStartTime
        )
    }

    /// Destroy infrastructure
    /// - Parameter output: Optional client-owned stream to receive output (in addition to global stream)
    public func destroy(output: CLIOutputStream? = nil) async throws {
        infrastructureStatus.status = .destroying
        infrastructureStatus.deployStartTime = Date()
        infrastructureStatus.deploymentProgress.clear()

        do {
            // Run CDK destroy in background while polling for progress
            try await runDeployWithProgressPolling {
                try await self.cdkService.destroy(force: true, output: output)
            }

            infrastructureStatus.status = .notDeployed
            infrastructureStatus.configuration = CDKInfrastructureStatus.Configuration()
            infrastructureStatus.outputs = CDKInfrastructureStatus.StackOutputs()
        } catch {
            infrastructureStatus.status = .failed(reason: error.localizedDescription)
            infrastructureStatus.deployStartTime = nil
            infrastructureStatus.deploymentProgress.clear()
            throw error
        }
    }

    // MARK: - Private Helpers

    /// Monitor an existing in-progress operation (detected on app startup)
    /// Polls for progress until the operation completes, then refreshes status
    private func monitorExistingOperation() async {
        infrastructureStatus.deployStartTime = Date()
        infrastructureStatus.deploymentProgress.clear()

        let stackName = infrastructureStatus.stackName
        let pollInterval: Duration = .seconds(2)

        // Poll until operation completes
        while infrastructureStatus.status.isBusy {
            do {
                // Update progress from events
                let events = try await awsService.getStackEvents(name: stackName)
                infrastructureStatus.deploymentProgress.update(
                    from: events,
                    since: nil  // Show all recent events since we don't know when it started
                )

                // Check if operation is still in progress
                if let status = try? await awsService.getStackStatus(name: stackName) {
                    switch status {
                    case CloudFormationStackStatus.createInProgress,
                         CloudFormationStackStatus.updateInProgress,
                         CloudFormationStackStatus.updateCompleteCleanupInProgress,
                         CloudFormationStackStatus.deleteInProgress:
                        // Still in progress, continue polling
                        break
                    default:
                        // Operation finished, refresh to get final state
                        infrastructureStatus.deployStartTime = nil
                        infrastructureStatus.deploymentProgress.clear()
                        await refreshStatus(force: true)
                        return
                    }
                }
            } catch {
                // Error polling, increment poll count anyway
                infrastructureStatus.deploymentProgress.pollCount += 1
            }

            try? await Task.sleep(for: pollInterval)
        }
    }

    private func queryConfiguration() async throws -> CDKInfrastructureStatus.Configuration {
        let resources = try await awsService.describeStackResources(name: infrastructureStatus.stackName)

        return CDKInfrastructureStatus.Configuration(
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

}
