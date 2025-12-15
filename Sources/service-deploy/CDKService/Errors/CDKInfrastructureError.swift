import Foundation

/// Typed errors for CDK Infrastructure operations
public enum CDKInfrastructureError: Error, Equatable, Sendable {
    case credentialExpired(message: String)
    case stackNotFound(stackName: String)
    case deploymentFailed(reason: String)
    case buildFailed(reason: String)
    case operationInProgress(operation: String)
    case unknown(message: String)

    public var localizedDescription: String {
        switch self {
        case .credentialExpired(let message):
            return "AWS credentials expired: \(message)"
        case .stackNotFound(let stackName):
            return "Stack not found: \(stackName)"
        case .deploymentFailed(let reason):
            return "Deployment failed: \(reason)"
        case .buildFailed(let reason):
            return "Build failed: \(reason)"
        case .operationInProgress(let operation):
            return "Operation in progress: \(operation)"
        case .unknown(let message):
            return message
        }
    }

    /// Check if an error message indicates AWS credential issues
    public static func isCredentialError(_ error: String) -> Bool {
        let credentialPatterns = [
            "credentials missing",
            "credential_process",
            "Error getting temporary credentials",
            "ExpiredToken",
            "InvalidClientTokenId",
            "AccessDenied",
            "AuthFailure",
            "security token included in the request is invalid",
            "could not be found"
        ]
        return credentialPatterns.contains { error.localizedCaseInsensitiveContains($0) }
    }

    /// Check if an error message indicates the stack doesn't exist
    public static func isStackNotFoundError(_ error: String) -> Bool {
        let notFoundPatterns = [
            "does not exist",
            "Stack with id",
            "ValidationError"
        ]
        return notFoundPatterns.contains { error.localizedCaseInsensitiveContains($0) }
    }
}
