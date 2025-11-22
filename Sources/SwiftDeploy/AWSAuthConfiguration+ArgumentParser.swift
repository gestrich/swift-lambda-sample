//
//  AWSAuthConfiguration+ArgumentParser.swift
//  SwiftDeploy
//
//  ArgumentParser integration for AWSAuthConfiguration
//

import ArgumentParser

extension AWSAuthConfiguration {

    /// Help text for --aws-profile option
    public static var profileOptionHelp: ArgumentHelp {
        ArgumentHelp("AWS profile to use (reads from ~/.swiftSampleDemo/aws-config.json if not specified)")
    }
}
