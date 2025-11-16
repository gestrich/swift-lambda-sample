//
//  DirectInvocationEvent.swift
//  SwiftLambda
//
//  Represents direct Lambda invocations (not from API Gateway or CloudWatch)
//

import Foundation
import SwiftServerApp

/// Represents a direct Lambda invocation event
///
/// This is used for Lambda invocations that come from:
/// - AWS CLI: `aws lambda invoke --payload '...'`
/// - AWS SDK direct calls
/// - Another Lambda function
/// - AWS Step Functions
/// - AWS EventBridge (non-scheduled events)
///
/// This is distinct from:
/// - API Gateway requests (HTTP traffic)
/// - CloudWatch scheduled events (cron-based)
public enum DirectInvocationEvent: Decodable {
    case createUser(CreateUser)
    // Future direct invocation types can be added here:
    // case deleteUser(DeleteUser)
    // case updateUserSettings(UpdateUserSettings)
    // case processAnalytics(AnalyticsRequest)

    public init(from decoder: Decoder) throws {
        // Try to decode as CreateUser
        if let createUser = try? CreateUser(from: decoder) {
            self = .createUser(createUser)
            return
        }

        // Future: Add more direct invocation types here
        // if let deleteUser = try? DeleteUser(from: decoder) {
        //     self = .deleteUser(deleteUser)
        //     return
        // }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unable to decode direct invocation into any known type (CreateUser, ...)"
            )
        )
    }
}
