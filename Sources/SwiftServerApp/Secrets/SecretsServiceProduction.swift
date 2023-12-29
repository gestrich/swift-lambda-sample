//
//  SecretsServiceProduction.swift
//
//
//  Created by Bill Gestrich on 12/16/23.
//

import Foundation

public class SecretsServiceProduction: SecretsService {

    let awsSecretsService: SecretsServiceAWS

    public init(awsSecretsService: SecretsServiceAWS) {
        self.awsSecretsService = awsSecretsService
    }

    public func getSecret(identifier: String) async throws -> String {
        return try await awsSecretsService.getSecret(identifier: identifier)
    }
}
