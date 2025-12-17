//
//  AWSAuthConfiguration+ArgumentParser.swift
//  SwiftDeploy
//
//  ArgumentParser integration for AWSAuthConfiguration
//

import ArgumentParser
import d_sdk_aws
import c_service_deploy_remote
import c_service_deploy_core

extension AWSAuthConfiguration {

    /// Help text for --aws-profile option
    public static var profileOptionHelp: ArgumentHelp {
        ArgumentHelp("AWS profile to use (reads from ~/.swiftSampleDemo/aws-config.json if not specified)")
    }

    // MARK: - CLI Argument Resolution

    /// Resolve AWS configuration from CLI arguments (which override config file)
    /// - Parameters:
    ///   - cliProfileName: Optional profile name from --aws-profile flag
    ///   - cliUseAWSVault: Optional flag from --use-aws-vault (if specified, overrides config)
    /// - Returns: Resolved configuration
    /// - Throws: CLIError if no profile is configured
    public static func resolve(
        profileName cliProfileName: String?,
        useAWSVault cliUseAWSVault: Bool?
    ) throws -> AWSAuthConfiguration {
        let config = loadConfig()

        // Resolve profile (CLI overrides config)
        let profileName: String
        if let cliProfile = cliProfileName {
            profileName = cliProfile
        } else if let config = config {
            profileName = config.profileName
        } else {
            throw DeployError.invalidConfiguration(
                "AWS profile not specified. Either:\n" +
                "  1. Pass --aws-profile <name>, OR\n" +
                "  2. Configure profileName in ~/.swiftSampleDemo/aws-config.json\n\n" +
                "Example aws-config.json:\n" +
                "{\n" +
                "  \"profileName\": \"production\",\n" +
                "  \"useAWSVault\": false\n" +
                "}"
            )
        }

        // Resolve useAWSVault (CLI flag overrides config, otherwise defaults to false)
        let useAWSVault: Bool
        if let cliFlagValue = cliUseAWSVault {
            useAWSVault = cliFlagValue
        } else if let config = config {
            useAWSVault = config.useAWSVault
        } else {
            useAWSVault = false
        }

        return AWSAuthConfiguration(
            profileName: profileName,
            useAWSVault: useAWSVault
        )
    }
}
