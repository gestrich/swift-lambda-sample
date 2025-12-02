import Foundation

/// Protocol for services that provide local build capabilities
/// Only local services (XcodeLocalService, LinuxLocalService) conform to this protocol.
/// RemoteService does NOT conform - it uses CI/CD pipeline (GitHub Actions) for builds.
@MainActor
public protocol LocalBuildProvider: AnyObject {
    // MARK: - Build State

    /// Observable build state for UI
    var buildState: BuildState { get }

    // MARK: - Build Operations

    /// Build Lambda for the target platform, updating buildState
    /// - Parameter clean: Whether to clean build artifacts first
    /// - Throws: BuildError.failed if the build fails
    func build(clean: Bool) async throws

    /// Check if Lambda is already built
    func isLambdaBuilt() -> Bool

    /// Delete build artifacts and reset build state
    func deleteBuild() async throws

    /// Refresh build status by checking if artifacts exist on disk
    func refreshBuildStatus()
}

// MARK: - Default Implementations

extension LocalBuildProvider {
    /// Default implementation for build without clean parameter
    public func build() async throws {
        try await build(clean: false)
    }

    /// Default implementation for refreshing build status
    public func refreshBuildStatus() {
        buildState.updateFromDisk(buildExists: isLambdaBuilt())
    }
}
