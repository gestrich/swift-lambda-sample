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
            let snapshot = try await queryService.getFullStatus(stackName: infrastructureStatus.stackName)

            switch snapshot.state {
            case .deployed:
                infrastructureStatus.configuration = CDKInfrastructureStatus.Configuration(
                    hasDatabase: snapshot.configuration.hasDatabase,
                    hasNATGateway: snapshot.configuration.hasNATGateway,
                    hasVPC: snapshot.configuration.hasVPC
                )
                infrastructureStatus.outputs = CDKInfrastructureStatus.StackOutputs(
                    apiGatewayUrl: snapshot.outputs.apiGatewayUrl,
                    lambdaFunctionName: snapshot.outputs.lambdaFunctionName,
                    bucketName: snapshot.outputs.bucketName,
                    allOutputs: snapshot.outputs.allOutputs
                )
                infrastructureStatus.status = .deployed

            case .deploying(let operation):
                infrastructureStatus.status = .deploying(operation: operation)
                Task {
                    await monitorExistingOperation()
                }

            case .destroying:
                infrastructureStatus.status = .destroying
                Task {
                    await monitorExistingOperation()
                }

            case .failed(let reason):
                infrastructureStatus.status = .failed(reason: reason)

            case .notDeployed:
                infrastructureStatus.status = .notDeployed
                infrastructureStatus.configuration = CDKInfrastructureStatus.Configuration()
                infrastructureStatus.outputs = CDKInfrastructureStatus.StackOutputs()
            }
        } catch CDKInfrastructureError.credentialExpired(let message) {
            infrastructureStatus.status = .failed(reason: message)
        } catch {
            infrastructureStatus.status = .notDeployed
            infrastructureStatus.configuration = CDKInfrastructureStatus.Configuration()
            infrastructureStatus.outputs = CDKInfrastructureStatus.StackOutputs()
        }
    }

    /// Deploy infrastructure with specified configuration
    /// - Parameters:
    ///   - withPostgres: Include PostgreSQL database
    ///   - withNATGateway: Include NAT Gateway
    ///   - output: Optional client-owned stream to receive output
    public func deploy(withPostgres: Bool, withNATGateway: Bool, output: CLIOutputStream? = nil) async throws {
        infrastructureStatus.deployStartTime = Date()
        infrastructureStatus.deploymentProgress = CDKDeploymentProgress()
        infrastructureStatus.status = .deploying(operation: withPostgres ? "Deploying with Database" : "Deploying")

        do {
            let stream = queryService.deployWithProgress(
                stackName: infrastructureStatus.stackName,
                withPostgres: withPostgres,
                withNATGateway: withNATGateway,
                output: output
            )

            for try await progress in stream {
                infrastructureStatus.deploymentProgress = progress
            }

            infrastructureStatus.deployStartTime = nil
            infrastructureStatus.deploymentProgress = CDKDeploymentProgress()
            await refreshStatus(force: true)
        } catch {
            infrastructureStatus.status = .failed(reason: error.localizedDescription)
            infrastructureStatus.deployStartTime = nil
            infrastructureStatus.deploymentProgress = CDKDeploymentProgress()
            throw error
        }
    }

    /// Update infrastructure maintaining current configuration
    /// - Parameter output: Optional client-owned stream to receive output
    public func updateInfrastructure(output: CLIOutputStream? = nil) async throws {
        infrastructureStatus.deployStartTime = Date()
        infrastructureStatus.deploymentProgress = CDKDeploymentProgress()
        infrastructureStatus.status = .deploying(operation: "Updating")

        let hasDatabase = infrastructureStatus.configuration.hasDatabase
        let hasNATGateway = infrastructureStatus.configuration.hasNATGateway

        do {
            let stream = queryService.deployWithProgress(
                stackName: infrastructureStatus.stackName,
                withPostgres: hasDatabase,
                withNATGateway: hasNATGateway,
                output: output
            )

            for try await progress in stream {
                infrastructureStatus.deploymentProgress = progress
            }

            infrastructureStatus.deployStartTime = nil
            infrastructureStatus.deploymentProgress = CDKDeploymentProgress()
            await refreshStatus(force: true)
        } catch {
            infrastructureStatus.status = .failed(reason: error.localizedDescription)
            infrastructureStatus.deployStartTime = nil
            infrastructureStatus.deploymentProgress = CDKDeploymentProgress()
            throw error
        }
    }

    /// Destroy infrastructure
    /// - Parameter output: Optional client-owned stream to receive output
    public func destroy(output: CLIOutputStream? = nil) async throws {
        infrastructureStatus.status = .destroying
        infrastructureStatus.deployStartTime = Date()
        infrastructureStatus.deploymentProgress = CDKDeploymentProgress()

        do {
            let stream = queryService.destroyWithProgress(
                stackName: infrastructureStatus.stackName,
                output: output
            )

            for try await progress in stream {
                infrastructureStatus.deploymentProgress = progress
            }

            infrastructureStatus.status = .notDeployed
            infrastructureStatus.configuration = CDKInfrastructureStatus.Configuration()
            infrastructureStatus.outputs = CDKInfrastructureStatus.StackOutputs()
            infrastructureStatus.deployStartTime = nil
            infrastructureStatus.deploymentProgress = CDKDeploymentProgress()
        } catch {
            infrastructureStatus.status = .failed(reason: error.localizedDescription)
            infrastructureStatus.deployStartTime = nil
            infrastructureStatus.deploymentProgress = CDKDeploymentProgress()
            throw error
        }
    }

    // MARK: - Private

    /// Monitor an existing in-progress operation (detected on app startup)
    private func monitorExistingOperation() async {
        infrastructureStatus.deployStartTime = Date()
        infrastructureStatus.deploymentProgress = CDKDeploymentProgress()

        do {
            let stream = queryService.monitorOperation(stackName: infrastructureStatus.stackName)

            for try await progress in stream {
                infrastructureStatus.deploymentProgress = progress

                if progress.isComplete {
                    break
                }
            }

            infrastructureStatus.deployStartTime = nil
            infrastructureStatus.deploymentProgress = CDKDeploymentProgress()
            await refreshStatus(force: true)
        } catch {
            infrastructureStatus.deployStartTime = nil
            infrastructureStatus.deploymentProgress = CDKDeploymentProgress()
            await refreshStatus(force: true)
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
    /// Uses the service's CDKDeploymentProgress type directly
    public var deploymentProgress: CDKDeploymentProgress = CDKDeploymentProgress()

    public init() {}

    /// Convenience computed properties for UI
    public var hasPolled: Bool { deploymentProgress.pollCount > 0 }
    public var hasPolledEnough: Bool { deploymentProgress.pollCount >= 5 }
}
