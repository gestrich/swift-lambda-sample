//
//  EnvironmentVariables.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 11/27/25.
//

import Foundation

func createEnvironmentVariables(postgresService: PostgreSQLService, minioService: MinIOService) -> [String: String] {
        let postgresInfo = postgresService.connectionInfo
        let minioCreds = minioService.credentials

        return [
            // PostgreSQL configuration
            "POSTGRES_HOST": postgresInfo.containerName,
            "POSTGRES_PORT": "\(postgresInfo.port)",
            "POSTGRES_USER_NAME": postgresInfo.username,
            "POSTGRES_DBNAME": postgresInfo.database,
            "POSTGRES_PASSWORD": postgresInfo.password,
            "POSTGRES_PASSWORD_SECRET_ID": "local-testing",  // Bypass Secrets Manager for local testing

            // S3/MinIO configuration
            "S3_BUCKET_NAME": minioService.bucketName,
            "AWS_ENDPOINT_URL": "http://\(minioService.minioContainerName):9000",
            "AWS_ACCESS_KEY_ID": minioCreds.accessKeyId,
            "AWS_SECRET_ACCESS_KEY": minioCreds.secretAccessKey,
            "AWS_REGION": minioCreds.region,
            "AWS_DEFAULT_REGION": minioCreds.region,

            // Disable AWS credential chain for local testing
            "AWS_EC2_METADATA_DISABLED": "true",
            "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI": "",  // Disable ECS credentials

            // Local Lambda server configuration
            "MOCK_AWS_CREDENTIALS": "true",
            "LOCAL_LAMBDA_SERVER_ENABLED": "true",
            "LOCAL_LAMBDA_HOST": "0.0.0.0"
        ]
    }
