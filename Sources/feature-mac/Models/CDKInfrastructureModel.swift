import sdk_cli
import Foundation
import Observation
import service_deploy

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

    /// Initialize with an injected query service (preferred for testability)
    public init(queryService: CDKInfrastructureQueryService) {
        self.queryService = queryService

        // Fetch status from AWS immediately on init
        Task {
            await self.refreshStatus()
        }
    }

    /// Convenience initializer that creates the query service internally
    public convenience init(
        projectRoot: String,
        awsConfig: AWSAuthConfiguration,
        cdkDirectory: String = CDKStackConfiguration.defaultCDKDirectory,
        cliService: CLIService
    ) {
        let queryService = CDKInfrastructureQueryService(
            projectRoot: projectRoot,
            awsConfig: awsConfig,
            cdkDirectory: cdkDirectory,
            cliService: cliService
        )
        self.init(queryService: queryService)
    }

    // MARK: - UI State Operations

    /// Refresh infrastructure status from AWS
    /// - Parameter force: If true, bypasses the isBusy check (used after operations complete)
    public func refreshStatus(force: Bool = false) async {
        guard force || !infrastructureStatus.status.isBusy else { return }

        infrastructureStatus.status = .loading

        do {
            let stackName = infrastructureStatus.stackName
            infrastructureStatus = try await queryService.getFullStatus(stackName: stackName)

            if infrastructureStatus.status.isBusy {
                Task { await monitorExistingOperation() }
            }
        } catch CDKInfrastructureError.credentialExpired(let message) {
            infrastructureStatus.status = .failed(reason: message)
        } catch {
            infrastructureStatus.status = .failed(reason: error.localizedDescription)
        }
    }

    /// Deploy infrastructure with specified configuration
    public func deploy(withPostgres: Bool, withNATGateway: Bool, output: CLIOutputStream? = nil) async throws {
        beginOperation(status: .deploying(operation: withPostgres ? "Deploying with Database" : "Deploying"))

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

            endOperation()
            await refreshStatus(force: true)
        } catch {
            endOperation(failed: error.localizedDescription)
            throw error
        }
    }

    /// Update infrastructure maintaining current configuration
    public func updateInfrastructure(output: CLIOutputStream? = nil) async throws {
        beginOperation(status: .deploying(operation: "Updating"))

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

            endOperation()
            await refreshStatus(force: true)
        } catch {
            endOperation(failed: error.localizedDescription)
            throw error
        }
    }

    /// Destroy infrastructure
    public func destroy(output: CLIOutputStream? = nil) async throws {
        beginOperation(status: .destroying)

        do {
            let stream = queryService.destroyWithProgress(
                stackName: infrastructureStatus.stackName,
                output: output
            )

            for try await progress in stream {
                infrastructureStatus.deploymentProgress = progress
            }

            endOperation()
            await refreshStatus(force: true)
        } catch {
            endOperation(failed: error.localizedDescription)
            throw error
        }
    }

    // MARK: - Private Helpers

    /// Begin an operation - sets transient UI state
    private func beginOperation(status: CDKInfrastructureStatus.StackStatus) {
        infrastructureStatus.status = status
        infrastructureStatus.deployStartTime = Date()
        infrastructureStatus.deploymentProgress = CDKDeploymentProgress()
    }

    /// End an operation - clears transient UI state
    private func endOperation(failed reason: String? = nil) {
        infrastructureStatus.deployStartTime = nil
        infrastructureStatus.deploymentProgress = CDKDeploymentProgress()
        if let reason = reason {
            infrastructureStatus.status = .failed(reason: reason)
        }
    }

    /// Monitor an existing in-progress operation (detected on app startup)
    private func monitorExistingOperation() async {
        infrastructureStatus.deployStartTime = Date()
        infrastructureStatus.deploymentProgress = CDKDeploymentProgress()

        do {
            let stream = queryService.monitorOperation(stackName: infrastructureStatus.stackName)

            for try await progress in stream {
                infrastructureStatus.deploymentProgress = progress
                if progress.isComplete { break }
            }
        } catch {
            // Monitoring failed, just refresh to get current state
        }

        endOperation()
        await refreshStatus(force: true)
    }
}
