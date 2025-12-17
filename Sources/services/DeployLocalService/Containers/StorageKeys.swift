import StorageService

// MARK: - PostgreSQL Storage Keys

/// Storage key for PostgreSQL Xcode workflow data
public struct PostgreSQLXcodeStorageKey: StoragePathKey {
    public static let pathComponent = "postgres/xcode-data"
}

/// Storage key for PostgreSQL Linux workflow data
public struct PostgreSQLLinuxStorageKey: StoragePathKey {
    public static let pathComponent = "postgres/linux-data"
}

// MARK: - MinIO Storage Keys

/// Storage key for MinIO Xcode workflow data
public struct MinIOXcodeStorageKey: StoragePathKey {
    public static let pathComponent = "minio/xcode-data"
}

/// Storage key for MinIO Linux workflow data
public struct MinIOLinuxStorageKey: StoragePathKey {
    public static let pathComponent = "minio/linux-data"
}

// MARK: - DynamoDB Local Storage Keys

/// Storage key for DynamoDB Local Xcode workflow data
public struct DynamoDBLocalXcodeStorageKey: StoragePathKey {
    public static let pathComponent = "dynamodb/xcode-data"
}

/// Storage key for DynamoDB Local Linux workflow data
public struct DynamoDBLocalLinuxStorageKey: StoragePathKey {
    public static let pathComponent = "dynamodb/linux-data"
}
