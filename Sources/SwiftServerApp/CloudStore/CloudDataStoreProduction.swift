//
//  CloudDataStoreProduction.swift
//
//
//  Created by Bill Gestrich on 12/17/23.
//

import Foundation

public actor CloudDataStoreProduction: CloudDataStore {

    private var cloudStore: CloudDataStore? = nil
    private let cloudStoreFactory: () async throws -> CloudDataStore

    public init(cloudStoreFactory: @escaping () async throws -> CloudDataStore) {
        self.cloudStoreFactory = cloudStoreFactory
    }

    private func getOrCreateCloudStore() async throws -> CloudDataStore {
        if let cloudStore {
            return cloudStore
        } else {
            let result = try await cloudStoreFactory()
            cloudStore = result
            return result
        }
    }

    public func getData(key: String) async throws -> Data? {
        let cloudStore = try await getOrCreateCloudStore()
        return try await cloudStore.getData(key: key)
    }

    public func uploadData(_ data: Data, key: String) async throws {
        let cloudStore = try await getOrCreateCloudStore()
        _ = try await cloudStore.uploadData(data, key: key)

    }
}

