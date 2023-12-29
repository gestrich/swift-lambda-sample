//
//  CloudDataStore.swift
//
//
//  Created by Bill Gestrich on 12/4/23.
//

import Foundation

public protocol CloudDataStore {
    func getData(key: String) async throws -> Data?
    func uploadData(_ data: Data, key: String) async throws
}
