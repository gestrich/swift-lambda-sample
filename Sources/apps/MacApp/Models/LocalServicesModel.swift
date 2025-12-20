import Foundation
import CLISDK
import StorageService
import DeployLocalService
import LocalServicesFeature

/// Observable model for managing local Docker services (PostgreSQL, MinIO, DynamoDB).
/// Acts as a child model that can be owned by parent models (DeployXcodeModel, DeployLinuxModel).
/// Views can access this model directly for service operations.
@MainActor
public class LocalServicesModel {
    private let workingDirectory: String
    private let configuration: LocalServicesConfiguration
    private let storageService: LocalStorageService

    // MARK: - Unified State

    /// Unified state machine for all service operations.
    public private(set) var state: ModelState = .uninitialized

    // MARK: - Derived Properties

    /// Whether the model is idle (not loading or operating).
    public var isIdle: Bool { state.isIdle }

    /// Whether a start operation can be performed.
    public var canStart: Bool { state.canStart }

    /// Whether a stop operation can be performed.
    public var canStop: Bool { state.canStop }

    /// Current services snapshot (from ready state or prior state during loading/operation).
    public var snapshot: LocalServicesSnapshot? { state.snapshot }

    /// The active use case state, if operating.
    public var useCaseState: LocalServicesUseCaseState? { state.useCaseState }

    /// Start time of the current operation, if any.
    public var operationStartTime: Date? { state.operationStartTime }

    // MARK: - Data Directories

    public var s3DataDirectory: String {
        storageService.dataDirectory(for: configuration.minioStorageKey)
    }

    public var postgresDataDirectory: String {
        storageService.dataDirectory(for: configuration.postgresStorageKey)
    }

    public var dynamodbDataDirectory: String {
        storageService.dataDirectory(for: configuration.dynamodbStorageKey)
    }

    // MARK: - Initialization

    public init(workingDirectory: String, configuration: LocalServicesConfiguration) {
        self.workingDirectory = workingDirectory
        self.configuration = configuration
        self.storageService = LocalStorageService()
        Task { await refresh() }
    }

    // MARK: - Service Management

    /// Start all local services (PostgreSQL, MinIO S3, DynamoDB Local).
    public func startAllServices() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = StartServicesUseCase.create(
            workingDirectory: workingDirectory,
            configuration: configuration
        )

        do {
            for try await useCaseState in components.useCase.stream(options: .all) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Stop all local services (PostgreSQL, MinIO S3, DynamoDB Local).
    public func stopAllServices() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = StopServicesUseCase.create(
            workingDirectory: workingDirectory,
            configuration: configuration
        )

        do {
            for try await useCaseState in components.useCase.stream(options: .all) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Start MinIO S3 service.
    public func startS3() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = StartServicesUseCase.create(
            workingDirectory: workingDirectory,
            configuration: configuration
        )

        do {
            for try await useCaseState in components.useCase.stream(options: .only(.s3)) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Stop MinIO S3 service.
    public func stopS3() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = StopServicesUseCase.create(
            workingDirectory: workingDirectory,
            configuration: configuration
        )

        do {
            for try await useCaseState in components.useCase.stream(options: .only(.s3)) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Start PostgreSQL database service.
    public func startDatabase() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = StartServicesUseCase.create(
            workingDirectory: workingDirectory,
            configuration: configuration
        )

        do {
            for try await useCaseState in components.useCase.stream(options: .only(.database)) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Stop PostgreSQL database service.
    public func stopDatabase() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = StopServicesUseCase.create(
            workingDirectory: workingDirectory,
            configuration: configuration
        )

        do {
            for try await useCaseState in components.useCase.stream(options: .only(.database)) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Start DynamoDB Local service.
    public func startDynamoDB() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = StartServicesUseCase.create(
            workingDirectory: workingDirectory,
            configuration: configuration
        )

        do {
            for try await useCaseState in components.useCase.stream(options: .only(.dynamodb)) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Stop DynamoDB Local service.
    public func stopDynamoDB() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = StopServicesUseCase.create(
            workingDirectory: workingDirectory,
            configuration: configuration
        )

        do {
            for try await useCaseState in components.useCase.stream(options: .only(.dynamodb)) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Create S3 bucket in MinIO.
    public func createBucket(bucketName: String? = nil) async throws {
        let components = StartServicesUseCase.create(
            workingDirectory: workingDirectory,
            configuration: configuration
        )
        try await components.minioClient.createBucket(bucketName: bucketName)
    }

    // MARK: - Status

    /// Refresh services status from Docker.
    @discardableResult
    public func refresh() async -> LocalServicesSnapshot? {
        guard state.isIdle else { return nil }

        let prior = snapshot
        state = .loading(prior: prior)

        let components = ServicesStatusUseCase.create(
            workingDirectory: workingDirectory,
            configuration: configuration
        )

        do {
            for try await useCaseState in components.useCase.stream(options: ()) {
                state = ModelState(from: useCaseState, prior: prior)
            }
            return state.snapshot
        } catch {
            state = ModelState(error: error, preserving: prior)
            return nil
        }
    }
}

// MARK: - Model State

extension LocalServicesModel {
    /// Unified state machine for local services model.
    public enum ModelState: Equatable {
        /// Initial state before any operation
        case uninitialized

        /// Loading/refreshing state (preserves prior state if available)
        case loading(prior: LocalServicesSnapshot?)

        /// Ready state with current services info
        case ready(LocalServicesSnapshot)

        /// Active use case in progress
        case operating(LocalServicesUseCaseState, prior: LocalServicesSnapshot?)

        // MARK: - Convenience Initializers

        /// Construct ModelState from a use case state plus prior snapshot.
        public init(from useCaseState: LocalServicesUseCaseState, prior: LocalServicesSnapshot?) {
            if let snapshot = useCaseState.completedSnapshot {
                self = .ready(snapshot)
            } else {
                self = .operating(useCaseState, prior: prior)
            }
        }

        /// Construct a failed ModelState from a caught error.
        public init(error: Error, preserving prior: LocalServicesSnapshot?) {
            self = .ready(prior ?? .stopped)
        }

        // MARK: - Convenience Accessors

        /// Current services info (from ready state or prior state during loading/operation)
        public var snapshot: LocalServicesSnapshot? {
            switch self {
            case .uninitialized:
                return nil
            case .loading(let prior):
                return prior
            case .ready(let snapshot):
                return snapshot
            case .operating(_, let prior):
                return prior
            }
        }

        /// The active use case state, if operating
        public var useCaseState: LocalServicesUseCaseState? {
            guard case .operating(let state, _) = self else { return nil }
            return state
        }

        /// Whether the model is idle (not loading or operating)
        public var isIdle: Bool {
            switch self {
            case .uninitialized, .ready:
                return true
            case .loading, .operating:
                return false
            }
        }

        /// Whether a start operation can be performed
        public var canStart: Bool {
            switch self {
            case .ready(let snapshot):
                return snapshot.canStart
            case .uninitialized:
                return true
            case .loading, .operating:
                return false
            }
        }

        /// Whether a stop operation can be performed
        public var canStop: Bool {
            switch self {
            case .ready(let snapshot):
                return snapshot.canStop
            case .uninitialized, .loading, .operating:
                return false
            }
        }

        /// Start time of the current operation, if any
        public var operationStartTime: Date? {
            useCaseState?.startTime
        }
    }
}
