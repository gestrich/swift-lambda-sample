import CLIKit
import Foundation
import Observation
import SwiftDeploy

/// Observable model for CDK Infrastructure state management
/// Holds UI state and delegates operations to CDKInfrastructureQueryService
@MainActor
@Observable
public final class CDKInfrastructureModel {
    // MARK: - State (source of truth)

    public private(set) var infrastructureStatus = CDKInfrastructureStatus()

    // MARK: - Private Services

    private let queryService: CDKInfrastructureQueryService

    // MARK: - Init

    public init(
        projectRoot: String,
        awsConfig: AWSAuthConfiguration,
        cdkDirectory: String = "cdk",
        cliService: CLIService
    ) {
        self.queryService = CDKInfrastructureQueryService(
            projectRoot: projectRoot,
            awsConfig: awsConfig,
            cdkDirectory: cdkDirectory,
            cliService: cliService
        )
    }

    // MARK: - UI State Operations

    /// Refresh infrastructure status including stack state, configuration, and outputs.
    /// - Parameter force: If true, bypasses the isBusy check (used after deploy/destroy completes)
    public func refreshStatus(force: Bool = false) async {
        guard force || !infrastructureStatus.status.isBusy else { return }

        infrastructureStatus.status = .loading

        do {
            let stackStatus = try await queryService.getStackStatus(stackName: infrastructureStatus.stackName)

            switch stackStatus {
            case CloudFormationStackStatusValues.createComplete,
                 CloudFormationStackStatusValues.updateComplete:
                let config = try await queryService.queryConfiguration(stackName: infrastructureStatus.stackName)
                let outputs = try await queryService.getStackOutputs(stackName: infrastructureStatus.stackName)

                infrastructureStatus.configuration = CDKInfrastructureStatus.Configuration(
                    hasDatabase: config.hasDatabase,
                    hasNATGateway: config.hasNATGateway,
                    hasVPC: config.hasVPC
                )
                infrastructureStatus.outputs = CDKInfrastructureStatus.StackOutputs.from(outputs)
                infrastructureStatus.status = .deployed

            case CloudFormationStackStatusValues.createInProgress,
                 CloudFormationStackStatusValues.updateInProgress,
                 CloudFormationStackStatusValues.updateCompleteCleanupInProgress:
                infrastructureStatus.status = .deploying(operation: "Updating")
                Task {
                    await monitorExistingOperation()
                }

            case CloudFormationStackStatusValues.deleteInProgress:
                infrastructureStatus.status = .destroying
                Task {
                    await monitorExistingOperation()
                }

            case CloudFormationStackStatusValues.createFailed,
                 CloudFormationStackStatusValues.updateFailed,
                 CloudFormationStackStatusValues.rollbackComplete,
                 CloudFormationStackStatusValues.rollbackFailed,
                 CloudFormationStackStatusValues.deleteFailed:
                infrastructureStatus.status = .failed(reason: stackStatus)

            default:
                infrastructureStatus.status = .deployed
            }
        } catch {
            let errorMessage = error.localizedDescription

            if Self.isCredentialError(errorMessage) {
                infrastructureStatus.status = .failed(reason: errorMessage)
            } else {
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
            "could not be found"
        ]
        return credentialPatterns.contains { error.localizedCaseInsensitiveContains($0) }
    }

    /// Deploy infrastructure with specified configuration
    /// - Parameters:
    ///   - withPostgres: Include PostgreSQL database
    ///   - withNATGateway: Include NAT Gateway
    ///   - output: Optional client-owned stream to receive output
    public func deploy(withPostgres: Bool, withNATGateway: Bool, output: CLIOutputStream? = nil) async throws {
        infrastructureStatus.deployStartTime = Date()
        infrastructureStatus.deploymentProgress.clear()
        infrastructureStatus.status = .deploying(operation: withPostgres ? "Deploying with Database" : "Deploying")

        do {
            try await queryService.build(output: output)

            try await runDeployWithProgressPolling {
                try await self.queryService.deploy(withPostgres: withPostgres, withNATGateway: withNATGateway, output: output)
            }

            await refreshStatus(force: true)
        } catch {
            infrastructureStatus.status = .failed(reason: error.localizedDescription)
            infrastructureStatus.deployStartTime = nil
            infrastructureStatus.deploymentProgress.clear()
            throw error
        }
    }

    /// Update infrastructure maintaining current configuration
    /// - Parameter output: Optional client-owned stream to receive output
    public func updateInfrastructure(output: CLIOutputStream? = nil) async throws {
        infrastructureStatus.deployStartTime = Date()
        infrastructureStatus.deploymentProgress.clear()
        infrastructureStatus.status = .deploying(operation: "Updating")

        // Capture current configuration before entering detached task
        let hasDatabase = infrastructureStatus.configuration.hasDatabase
        let hasNATGateway = infrastructureStatus.configuration.hasNATGateway

        do {
            try await queryService.build(output: output)

            try await runDeployWithProgressPolling {
                try await self.queryService.deploy(
                    withPostgres: hasDatabase,
                    withNATGateway: hasNATGateway,
                    output: output
                )
            }

            await refreshStatus(force: true)
        } catch {
            infrastructureStatus.status = .failed(reason: error.localizedDescription)
            infrastructureStatus.deployStartTime = nil
            infrastructureStatus.deploymentProgress.clear()
            throw error
        }
    }

    /// Destroy infrastructure
    /// - Parameter output: Optional client-owned stream to receive output
    public func destroy(output: CLIOutputStream? = nil) async throws {
        infrastructureStatus.status = .destroying
        infrastructureStatus.deployStartTime = Date()
        infrastructureStatus.deploymentProgress.clear()

        do {
            try await runDeployWithProgressPolling {
                try await self.queryService.destroy(output: output)
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

    // MARK: - Private Progress Polling

    /// Run a CDK operation while polling for CloudFormation progress
    private func runDeployWithProgressPolling(_ cdkOperation: @escaping @Sendable () async throws -> Void) async throws {
        let stackName = infrastructureStatus.stackName
        let startTime = infrastructureStatus.deployStartTime

        let pollingTask = Task.detached { [queryService] in
            await self.pollProgressUntilCancelled(
                stackName: stackName,
                startTime: startTime,
                queryService: queryService
            )
        }

        let cdkTask = Task.detached {
            try await cdkOperation()
        }

        do {
            try await cdkTask.value
        } catch {
            pollingTask.cancel()
            throw error
        }

        pollingTask.cancel()

        try? await updateProgressOnce()

        infrastructureStatus.deployStartTime = nil
        infrastructureStatus.deploymentProgress.clear()
    }

    /// Poll progress continuously until cancelled (runs off MainActor)
    private nonisolated func pollProgressUntilCancelled(
        stackName: String,
        startTime: Date?,
        queryService: CDKInfrastructureQueryService
    ) async {
        let pollInterval: Duration = .seconds(2)

        while !Task.isCancelled {
            do {
                let events = try await queryService.getStackEvents(stackName: stackName)

                await MainActor.run {
                    self.infrastructureStatus.deploymentProgress.update(
                        from: events,
                        since: startTime
                    )
                }
            } catch {
                await MainActor.run {
                    self.infrastructureStatus.deploymentProgress.pollCount += 1
                }
            }

            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                break
            }
        }
    }

    /// Single progress update (runs on MainActor)
    private func updateProgressOnce() async throws {
        let events = try await queryService.getStackEvents(stackName: infrastructureStatus.stackName)
        infrastructureStatus.deploymentProgress.update(
            from: events,
            since: infrastructureStatus.deployStartTime
        )
    }

    /// Monitor an existing in-progress operation (detected on app startup)
    private func monitorExistingOperation() async {
        infrastructureStatus.deployStartTime = Date()
        infrastructureStatus.deploymentProgress.clear()

        let stackName = infrastructureStatus.stackName
        let pollInterval: Duration = .seconds(2)

        while infrastructureStatus.status.isBusy {
            do {
                let events = try await queryService.getStackEvents(stackName: stackName)
                infrastructureStatus.deploymentProgress.update(
                    from: events,
                    since: nil
                )

                if let status = try? await queryService.getStackStatus(stackName: stackName) {
                    switch status {
                    case CloudFormationStackStatusValues.createInProgress,
                         CloudFormationStackStatusValues.updateInProgress,
                         CloudFormationStackStatusValues.updateCompleteCleanupInProgress,
                         CloudFormationStackStatusValues.deleteInProgress:
                        break
                    default:
                        infrastructureStatus.deployStartTime = nil
                        infrastructureStatus.deploymentProgress.clear()
                        await refreshStatus(force: true)
                        return
                    }
                }
            } catch {
                infrastructureStatus.deploymentProgress.pollCount += 1
            }

            try? await Task.sleep(for: pollInterval)
        }
    }
}

// MARK: - UI State Types

/// State for CDK Infrastructure tracking
public struct CDKInfrastructureStatus: Equatable, Sendable {
    public enum StackStatus: Equatable, Sendable {
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
    public struct Configuration: Equatable, Sendable {
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
    public struct StackOutputs: Equatable, Sendable {
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
    public struct DeploymentProgress: Equatable, Sendable {
        public var resources: [ResourceProgress] = []
        public var totalExpected: Int?

        public var completedCount: Int {
            resources.filter { $0.status.isComplete }.count
        }

        public var inProgressCount: Int {
            resources.filter { $0.status.isInProgress }.count
        }

        public var hasFailures: Bool {
            resources.contains { $0.status.isFailed }
        }

        public init() {}

        public var pollCount: Int = 0

        public var hasPolled: Bool { pollCount > 0 }

        public var hasPolledEnough: Bool { pollCount >= 5 }

        public mutating func update(from events: [CloudFormationStackEvent], since: Date?) {
            pollCount += 1

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
    public struct ResourceProgress: Equatable, Identifiable, Sendable {
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
    public enum ResourceStatus: Equatable, Sendable {
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
