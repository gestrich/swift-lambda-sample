//
//  AWSCredentialProvider.swift
//  sdk-aws
//
//  Protocol for AWS credential strategies
//

import Foundation

/// Protocol for providing AWS credentials to CLI commands
public protocol AWSCredentialProvider: Sendable {
    /// Wrap a command with credential configuration
    /// - Parameters:
    ///   - command: The base command (e.g., "aws", "cdk")
    ///   - arguments: The command arguments
    /// - Returns: Tuple with potentially modified command and arguments
    func wrapCommand(
        command: String,
        arguments: [String]
    ) -> (command: String, arguments: [String])
}

/// Credential provider using AWS profile
public struct ProfileCredentialProvider: AWSCredentialProvider {
    public let profileName: String

    public init(profileName: String) {
        self.profileName = profileName
    }

    public func wrapCommand(
        command: String,
        arguments: [String]
    ) -> (command: String, arguments: [String]) {
        var args = arguments
        // Add --profile flag for AWS CLI commands
        if command == "aws" && !args.contains("--profile") {
            args.append(contentsOf: ["--profile", profileName])
        }
        return (command, args)
    }
}

/// Credential provider using aws-vault
public struct VaultCredentialProvider: AWSCredentialProvider {
    private let vaultService: AWSVaultService

    public init(profile: String) {
        self.vaultService = AWSVaultService(profile: profile)
    }

    public func wrapCommand(
        command: String,
        arguments: [String]
    ) -> (command: String, arguments: [String]) {
        // Remove any existing --profile flags (aws-vault handles auth)
        let filteredArgs = AWSVaultService.removeProfileFlags(from: arguments)
        return vaultService.wrapCommand(command: command, arguments: filteredArgs)
    }
}

// MARK: - Factory

extension AWSAuthConfiguration {
    /// Create a credential provider based on this configuration
    public func makeCredentialProvider() -> any AWSCredentialProvider {
        if useAWSVault {
            return VaultCredentialProvider(profile: profileName)
        } else {
            return ProfileCredentialProvider(profileName: profileName)
        }
    }
}
