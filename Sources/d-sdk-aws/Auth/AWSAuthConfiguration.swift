//
//  AWSAuthConfiguration.swift
//  sdk-aws
//
//  AWS authentication configuration for deployment tooling
//

import Foundation

/// AWS authentication configuration
public struct AWSAuthConfiguration: Codable, Sendable {
    public let profileName: String
    public let useAWSVault: Bool

    public init(profileName: String, useAWSVault: Bool = false) {
        self.profileName = profileName
        self.useAWSVault = useAWSVault
    }
}
