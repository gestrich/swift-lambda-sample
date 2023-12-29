//
//  S3Configuration.swift
//
//
//  Created by Bill Gestrich on 12/16/23.
//

import Foundation

public struct S3Configuration: Codable {
    public let bucketName: String
    public let endpoint: String?

    public init(bucketName: String, endpoint: String?) {
        self.bucketName = bucketName
        self.endpoint = endpoint
    }
}
