//
//  S3DataStoreProduction.swift
//
//
//  Created by Bill Gestrich on 12/17/23.
//

import Foundation

public actor S3DataStoreProduction: S3DataStoreInterface, Sendable {

    private var s3Store: S3DataStoreInterface? = nil
    private let s3StoreFactory: () async throws -> S3DataStoreInterface

    public init(s3StoreFactory: @escaping () async throws -> S3DataStoreInterface) {
        self.s3StoreFactory = s3StoreFactory
    }

    private func getOrCreateS3Store() async throws -> S3DataStoreInterface {
        if let s3Store {
            return s3Store
        } else {
            let result = try await s3StoreFactory()
            s3Store = result
            return result
        }
    }

    public func getData(key: String) async throws -> Data? {
        let s3Store = try await getOrCreateS3Store()
        return try await s3Store.getData(key: key)
    }

    public func uploadData(_ data: Data, key: String) async throws {
        let s3Store = try await getOrCreateS3Store()
        _ = try await s3Store.uploadData(data, key: key)
    }

    public func listFiles() async throws -> [String] {
        let s3Store = try await getOrCreateS3Store()
        return try await s3Store.listFiles()
    }
}

