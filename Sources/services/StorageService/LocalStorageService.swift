import Foundation

/// Service for resolving local storage paths
/// All data is stored under ~/.swiftSampleDemo/
public struct LocalStorageService: Sendable {

    private let baseDirectory: String

    /// Initialize with default base directory (~/.swiftSampleDemo)
    public init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        self.baseDirectory = "\(homeDir)/.swiftSampleDemo"
    }

    /// Initialize with custom base directory (useful for testing)
    public init(baseDirectory: String) {
        self.baseDirectory = baseDirectory
    }

    /// The base directory for all local storage
    public var baseDataDirectory: String {
        baseDirectory
    }

    /// Get the data directory for a storage key
    /// - Parameter key: The storage key type
    /// - Returns: Full path to the data directory
    public func dataDirectory<K: StoragePathKey>(for key: K.Type) -> String {
        "\(baseDirectory)/\(K.pathComponent)"
    }

    /// Get the data directory for a storage key type (existential version)
    /// - Parameter keyType: The storage key type
    /// - Returns: Full path to the data directory
    public func dataDirectory(for keyType: any StoragePathKey.Type) -> String {
        "\(baseDirectory)/\(keyType.pathComponent)"
    }

    /// Get the path to a specific file
    /// - Parameter key: The file key type
    /// - Returns: Full path to the file
    public func filePath<K: StorageFileKey>(for key: K.Type) -> String {
        "\(baseDirectory)/\(K.filename)"
    }

    /// Ensure a directory exists, creating it if necessary
    /// - Parameter path: The directory path to ensure exists
    public func ensureDirectoryExists(at path: String) throws {
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    /// Ensure the data directory for a storage key exists
    /// - Parameter key: The storage key type
    public func ensureDataDirectoryExists<K: StoragePathKey>(for key: K.Type) throws {
        let path = dataDirectory(for: key)
        try ensureDirectoryExists(at: path)
    }

    /// Ensure the data directory for a storage key type exists (existential version)
    /// - Parameter keyType: The storage key type
    public func ensureDataDirectoryExists(for keyType: any StoragePathKey.Type) throws {
        let path = dataDirectory(for: keyType)
        try ensureDirectoryExists(at: path)
    }
}

/// Protocol for defining storage path keys
/// Clients define their own keys by conforming to this protocol
public protocol StoragePathKey: Sendable {
    /// The path component used in the directory structure
    /// e.g., "postgres/xcode-data", "minio/linux-data"
    static var pathComponent: String { get }
}

/// Protocol for keys that represent files (not directories)
public protocol StorageFileKey: StoragePathKey {
    /// The filename
    static var filename: String { get }
}

extension StorageFileKey {
    public static var pathComponent: String { filename }
}
