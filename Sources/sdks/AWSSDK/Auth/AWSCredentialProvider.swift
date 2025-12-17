//
//  AWSCredentialProvider.swift
//  sdk-aws
//
//  Protocol for AWS credential strategies
//

import CLISDK
import Foundation

/// Protocol for providing AWS credentials to CLI commands
public protocol AWSCredentialProvider: Sendable {
    /// The AWS profile name used for authentication
    var profileName: String { get }

    /// Environment variables to pass to CLI commands (e.g., AWS_PROFILE)
    var environment: [String: String] { get }

    /// Wrap a command with credential configuration
    /// - Parameters:
    ///   - command: The base command (e.g., "aws", "cdk")
    ///   - arguments: The command arguments
    /// - Returns: Tuple with potentially modified command and arguments
    func wrapCommand(
        command: String,
        arguments: [String]
    ) -> (command: String, arguments: [String])

    /// Build command line from a typed CLI command
    /// - Parameter command: The CLI command to build
    /// - Returns: Tuple with executable command and arguments
    func buildCommandLine<C: CLICommand>(_ command: C) -> (command: String, arguments: [String])
}

/// Credential provider using AWS profile
public struct ProfileCredentialProvider: AWSCredentialProvider {
    public let profileName: String

    public var environment: [String: String] {
        ["AWS_PROFILE": profileName]
    }

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

    public func buildCommandLine<C: CLICommand>(_ command: C) -> (command: String, arguments: [String]) {
        let programName = C.Program.programName
        let arguments = command.commandArguments
        return wrapCommand(command: programName, arguments: arguments)
    }
}

/// Credential provider using aws-vault
public struct VaultCredentialProvider: AWSCredentialProvider {
    public let profileName: String
    private let vaultClient: AWSVaultClient

    public var environment: [String: String] {
        // aws-vault injects credentials via environment, but we still need AWS_PROFILE
        // for commands that don't use aws-vault wrapping
        ["AWS_PROFILE": profileName]
    }

    public init(profile: String) {
        self.profileName = profile
        self.vaultClient = AWSVaultClient(profile: profile)
    }

    public func wrapCommand(
        command: String,
        arguments: [String]
    ) -> (command: String, arguments: [String]) {
        // Remove any existing --profile flags (aws-vault handles auth)
        let filteredArgs = AWSVaultClient.removeProfileFlags(from: arguments)
        return vaultClient.wrapCommand(command: command, arguments: filteredArgs)
    }

    public func buildCommandLine<C: CLICommand>(_ command: C) -> (command: String, arguments: [String]) {
        let programName = C.Program.programName
        let arguments = command.commandArguments
        return wrapCommand(command: programName, arguments: arguments)
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
