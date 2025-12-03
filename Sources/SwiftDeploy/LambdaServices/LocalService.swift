import Foundation

/// Combined protocol for local Lambda services (Xcode and Linux)
/// Combines LambdaService with all local-specific provider protocols.
/// Both XcodeLocalService and LinuxLocalService conform to this protocol.
@MainActor
public protocol LocalService: LambdaService, LocalDockerServicesProvider, LocalBuildProvider, LocalLambdaProvider {}
