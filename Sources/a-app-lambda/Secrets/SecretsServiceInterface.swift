//
//  SecretsServiceInterface.swift
//
//
//  Created by Bill Gestrich on 12/16/23.
//

import Foundation

public protocol SecretsServiceInterface: Sendable {
    func getSecret(identifier: String) async throws -> String
}
