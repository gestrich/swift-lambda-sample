//
//  S3DataStoreInterface.swift
//
//
//  Created by Bill Gestrich on 12/4/23.
//

import Foundation

public protocol S3DataStoreInterface: Sendable {
    func getData(key: String) async throws -> Data?
    func uploadData(_ data: Data, key: String) async throws
    func listFiles() async throws -> [String]
    func deleteFile(key: String) async throws
}
