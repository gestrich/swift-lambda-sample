import Foundation

/// Protocol for services that provide Docker-based local services (PostgreSQL, MinIO/S3)
/// Only local services (XcodeLocalService, LinuxLocalService) conform to this protocol.
/// RemoteService does NOT conform - it uses AWS-managed services instead.
@MainActor
public protocol LocalDockerServicesProvider: AnyObject {
    // MARK: - S3 (MinIO) Service Control

    /// Start MinIO S3 service
    func startS3() async throws

    /// Stop MinIO S3 service
    func stopS3() async throws

    // MARK: - Database (PostgreSQL) Service Control

    /// Start PostgreSQL database
    func startDatabase() async throws

    /// Stop PostgreSQL database
    func stopDatabase() async throws

    // MARK: - Data Directories

    /// Data directory for S3 (MinIO) - for UI to show "Open in Finder" button
    var s3DataDirectory: String { get }

    /// Data directory for PostgreSQL - for UI to show "Open in Finder" button
    var postgresDataDirectory: String { get }
}
