//
//  CloudDataStoreS3.swift
//  
//
//  Created by Bill Gestrich on 12/17/23.
//

import Foundation
import SotoS3

public class CloudDataStoreS3: CloudDataStore {

    private let s3: SotoS3.S3
    private let bucketName: String

    public init(awsClient: AWSClient, bucketName: String, endpoint: String?) {
        if let endpoint {
            self.s3 = SotoS3.S3(client: awsClient, endpoint: endpoint)
        } else {
            self.s3 = SotoS3.S3(client: awsClient)
        }
        self.bucketName = bucketName
    }

    public func getData(key: String) async throws -> Data? {
        let objRequest = S3.GetObjectRequest(bucket: bucketName, key: key)
        let s3Obj = try await self.s3.getObject(objRequest)
        return s3Obj.body?.asData()
    }

    public func uploadData(_ data: Data, key: String) async throws {
        let bodyData = data
        let putObjectRequest = SotoS3.S3.PutObjectRequest(
            acl: .private,
            body: .data(bodyData),
            bucket: bucketName,
            key: key
        )

        let _ = try await s3.putObject(putObjectRequest)

    }
}

