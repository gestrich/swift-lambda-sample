/// Represents CLI tools that are dependencies for this project
public enum CLITool: String, CaseIterable, Sendable {
    case homebrew
    case nodejs
    case docker
    case awsCLI
    case cdk
    case githubCLI

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .homebrew: return "Homebrew"
        case .nodejs: return "Node.js"
        case .docker: return "Docker"
        case .awsCLI: return "AWS CLI"
        case .cdk: return "CDK"
        case .githubCLI: return "GitHub CLI"
        }
    }
}
