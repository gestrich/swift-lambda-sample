import Foundation

/// Protocol for services that provide local Lambda lifecycle management
/// Only local services (XcodeLocalService, LinuxLocalService) conform to this protocol.
/// RemoteService does NOT conform - Lambda runs on-demand in AWS, managed by API Gateway.
@MainActor
public protocol LocalLambdaProvider: AnyObject {
    // MARK: - Lambda State

    /// Observable Lambda state for UI (streaming lifecycle output)
    var lambdaState: LambdaState { get }

    // MARK: - Lambda Lifecycle

    /// Start Lambda process/container only
    func startLambda() async throws

    /// Stop Lambda process/container only
    func stopLambda() async throws

    /// Start Lambda with all supporting services (PostgreSQL + S3)
    func startWithServices() async throws

    /// Stop Lambda and all supporting services
    func stopWithServices() async throws
}
