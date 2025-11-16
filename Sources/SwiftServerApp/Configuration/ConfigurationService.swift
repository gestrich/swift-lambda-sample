//
//  ConfigurationService.swift
//
//
//  Created by Bill Gestrich on 12/16/23.
//

import Foundation

public final class ConfigurationService: Sendable {

    private let configFileURL = Configuration.localConfigFileURL()
    private static var postgresUserPasswordIdentifierKey: String {
        get throws {
            guard let rawVal = getenv("POSTGRES_PASSWORD_SECRET_ID"),
                  let secretId = String(utf8String: rawVal) else {
                throw ConfigurationError.missingFromEnvVariables("POSTGRES_PASSWORD_SECRET_ID")
            }
            return secretId
        }
    }
    private let secretsService: SecretsServiceInterface

    public init(secretsService: SecretsServiceInterface) {
        self.secretsService = secretsService
    }

    private func configurationFromFile() async throws -> Configuration? {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            return nil
        }

        return try Configuration.loadConfiguration(fileURL: configFileURL)
    }

    //MARK: AWS Credentials 

    //MARK: Postgres

    public func postgresConfiguration() async throws -> PostgresConfiguration? {
        if let configuration = try await configurationFromFile() {
            return configuration.postgres
        } else {
            return try await postgresConfigurationFromEnvironment()
        }
    }

    private func postgresConfiguration(fileURL: URL) async throws -> PostgresConfiguration {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(PostgresConfiguration.self, from: data)
    }

    private func postgresConfigurationFromEnvironment() async throws -> PostgresConfiguration? {

        // Return nil if required environment variables are not set (database is optional)
        guard let databaseName = try? getEnvironmentVariable(key: "POSTGRES_DBNAME"),
              let databaseHost = try? getEnvironmentVariable(key: "POSTGRES_HOST"),
              let databasePortString = try? getEnvironmentVariable(key: "POSTGRES_PORT"),
              let databaseUserName = try? getEnvironmentVariable(key: "POSTGRES_USER_NAME") else {
            // Database environment variables not configured - database is optional
            return nil
        }

        let databaseIdentifier = "swift-sample-app" //TODO: Should this be configurable from environment?

        guard let port = Int(databasePortString) else {
            throw ConfigurationError.typeConversion("Could not convert port to Int: \(databasePortString)")
        }
        let tableName = "swift-sample-app" // try getEnvironmentVariable(key: "POSTGRES_TABLE_NAME")

        let secretString = try await secretsService.getSecret(identifier: try Self.postgresUserPasswordIdentifierKey)

        // Parse the secret as JSON to extract the password
        guard let secretData = secretString.data(using: .utf8),
              let secretJson = try? JSONSerialization.jsonObject(with: secretData) as? [String: Any],
              let databasePassword = secretJson["password"] as? String else {
            // Fallback: if secret is just a plain string (not JSON), use it directly
            return PostgresConfiguration(name: databaseName, identifier: databaseIdentifier, host: databaseHost, port: port, tableName: tableName, userName: databaseUserName, userPassword: secretString)
        }

        return PostgresConfiguration(name: databaseName, identifier: databaseIdentifier, host: databaseHost, port: port, tableName: tableName, userName: databaseUserName, userPassword: databasePassword)
    }

    //MARK: S3

    public func s3Configuration() async throws -> S3Configuration {
        if let configuration = try await configurationFromFile() {
            return configuration.s3
        } else {
            return try s3ConfigurationFromEnvironment()
        }
    }

    private func s3ConfigurationFromEnvironment() throws -> S3Configuration {
        let bucketName = try getEnvironmentVariable(key: "S3_BUCKET_NAME")
        return S3Configuration(bucketName: bucketName, endpoint: nil) //endpoint not yet supported from env variables.
    }

    //MARK: Util

    private enum ConfigurationError: LocalizedError {
        case missingFromEnvVariables(String)
        case typeConversion(String)

        var errorDescription: String? {
            switch self {
            case .missingFromEnvVariables(let message):
                return message
            case .typeConversion(let message):
                return message
            }
        }
    }

    private func getEnvironmentVariable(key: String) throws -> String {
        guard let rawVal = getenv(key) else {
            throw ConfigurationError.missingFromEnvVariables(key)
        }

        guard let result = String(utf8String: rawVal) else {
            throw ConfigurationError.typeConversion("Could not convert environment variable to string. Variable: \(key) Value: \(rawVal)")
        }

        return result
    }
}
