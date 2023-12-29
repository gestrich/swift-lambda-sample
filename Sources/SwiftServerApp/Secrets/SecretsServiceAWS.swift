//
//  SecretsServiceAWS.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/16/23.
//

import Foundation
import SotoSecretsManager

public class SecretsServiceAWS: SecretsService {

    let secretsManager: SecretsManager

    public init(awsClient: AWSClient) {
        self.secretsManager = SecretsManager(client: awsClient)
    }

    public func getSecret(identifier: String) async throws -> String {
        let result = try await secretsManager.getSecretValue(.init(secretId: identifier)).secretString
        guard let result else {
            throw SecretsServiceAWSError.missingSecret(identifier: identifier)
        }
        return result
    }

    enum SecretsServiceAWSError: LocalizedError {
        case missingSecret(identifier: String)

        var errorDescription: String? {
            switch self {
            case .missingSecret(let identifier):
                return "No secret for identifier: \(identifier)"
            }
        }
    }

}

