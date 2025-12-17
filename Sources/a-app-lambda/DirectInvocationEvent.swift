//
//  DirectInvocationEvent.swift
//  SwiftLambda
//
//  Represents direct Lambda invocations (not from API Gateway or CloudWatch)
//

import Foundation

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
public enum DirectInvocationEvent {
    case createUser(CreateUser)
    // Future direct invocation types can be added here:
    // case deleteUser(DeleteUser)
    // case updateUserSettings(UpdateUserSettings)
    // case processAnalytics(AnalyticsRequest)

    /// Attempts to decode the event as a known direct invocation type
    /// Returns nil if the JSON doesn't match any known direct invocation type
    public init?(from decoder: Decoder) {
        // Try to decode as CreateUser
        if let createUser = CreateUser.decode(from: decoder) {
            self = .createUser(createUser)
            return
        }

        // Future: Add more direct invocation types here
        // if let deleteUser = DeleteUser.decode(from: decoder) {
        //     self = .deleteUser(deleteUser)
        //     return
        // }

        // No match - return nil
        return nil
    }
}
