import Foundation

/// CloudFormation stack status values
/// See: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-describing-stacks.html
public enum CloudFormationStackStatusValues {
    // Successful states
    public static let createComplete = "CREATE_COMPLETE"
    public static let updateComplete = "UPDATE_COMPLETE"

    // In-progress states
    public static let createInProgress = "CREATE_IN_PROGRESS"
    public static let updateInProgress = "UPDATE_IN_PROGRESS"
    public static let updateCompleteCleanupInProgress = "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS"
    public static let deleteInProgress = "DELETE_IN_PROGRESS"

    // Failed states
    public static let createFailed = "CREATE_FAILED"
    public static let updateFailed = "UPDATE_FAILED"
    public static let rollbackComplete = "ROLLBACK_COMPLETE"
    public static let rollbackFailed = "ROLLBACK_FAILED"
    public static let deleteFailed = "DELETE_FAILED"

    /// Check if status indicates the stack is successfully deployed
    public static func isDeployed(_ status: String) -> Bool {
        status == createComplete || status == updateComplete
    }

    /// Check if status indicates an in-progress operation
    public static func isInProgress(_ status: String) -> Bool {
        switch status {
        case createInProgress, updateInProgress, updateCompleteCleanupInProgress, deleteInProgress:
            return true
        default:
            return false
        }
    }

    /// Check if status indicates a failed state
    public static func isFailed(_ status: String) -> Bool {
        switch status {
        case createFailed, updateFailed, rollbackComplete, rollbackFailed, deleteFailed:
            return true
        default:
            return false
        }
    }

    /// Check if status indicates a delete operation in progress
    public static func isDeleting(_ status: String) -> Bool {
        status == deleteInProgress
    }
}
