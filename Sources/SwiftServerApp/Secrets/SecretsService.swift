//
//  SecretsService.swift
//
//
//  Created by Bill Gestrich on 12/16/23.
//

import Foundation

public protocol SecretsService {
    func getSecret(identifier: String) async throws -> String
}
