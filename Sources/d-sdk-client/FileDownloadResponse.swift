//
//  FileDownloadResponse.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 11/23/25.
//

import Foundation

public struct FileDownloadResponse: Codable {
    public let fileName: String
    public let data: String  // base64 encoded

    public init(fileName: String, data: String) {
        self.fileName = fileName
        self.data = data
    }
}
