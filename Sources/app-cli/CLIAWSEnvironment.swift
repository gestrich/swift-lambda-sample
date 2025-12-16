//
//  CLIAWSEnvironment.swift
//  app-cli
//
//  Shared environment for AWS CLI commands
//

import Foundation
import sdk_aws
import sdk_cli

/// Shared environment for AWS CLI commands
struct CLIAWSEnvironment {
    let cliClient: CLIClient
    let projectRoot: String
    let credentialProvider: any AWSCredentialProvider
    let cdkDirectory: String

    /// Resolve AWS environment from CLI arguments
    /// - Parameters:
    ///   - awsProfile: Optional profile name from --aws-profile flag
    ///   - useAwsVault: Optional flag from --use-aws-vault
    ///   - cdkDirectory: CDK directory path relative to project root
    /// - Returns: Resolved environment
    /// - Throws: DeployError if configuration is invalid
    static func resolve(
        awsProfile: String?,
        useAwsVault: Bool?,
        cdkDirectory: String
    ) throws -> CLIAWSEnvironment {
        let awsConfig = try AWSAuthConfiguration.resolve(
            profileName: awsProfile,
            useAWSVault: useAwsVault
        )

        if awsProfile == nil {
            print("ℹ️  Using AWS profile '\(awsConfig.profileName)' from config file\n")
        }

        let projectRoot = FileManager.default.currentDirectoryPath
        let cliClient = CLIClient()
        let fullCdkPath = "\(projectRoot)/\(cdkDirectory)"

        return CLIAWSEnvironment(
            cliClient: cliClient,
            projectRoot: projectRoot,
            credentialProvider: awsConfig.makeCredentialProvider(),
            cdkDirectory: fullCdkPath
        )
    }
}
