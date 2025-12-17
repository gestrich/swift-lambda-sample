import d_sdk_cli
import Foundation

/// Client for Git operations
public actor GitClient {
    private let cliClient: CLIClient
    private let repoPath: String

    public init(repoPath: String, cliClient: CLIClient) {
        self.cliClient = cliClient
        self.repoPath = repoPath
    }

    /// Check if there are uncommitted changes
    public func hasUncommittedChanges() async throws -> Bool {
        let status: GitStatusResult = try await cliClient.execute(
            Git.Status(porcelain: true),
            parser: GitStatusParser(),
            workingDirectory: repoPath,
            printCommand: false
        )
        return status.hasChanges
    }

    /// Check if there are commits to push
    public func hasCommitsToPush() async throws -> Bool {
        let result = try await cliClient.executeForResult(
            Git.RevList(count: true, range: "@{u}..HEAD"),
            workingDirectory: repoPath,
            printCommand: false
        )

        guard result.isSuccess else {
            // If this fails, the branch might not have an upstream
            return false
        }

        let count = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(count) ?? 0 > 0
    }

    /// Get current branch name
    public func getCurrentBranch() async throws -> String {
        let result = try await cliClient.executeForResult(
            Git.Branch(showCurrent: true),
            workingDirectory: repoPath,
            printCommand: false
        )

        guard result.isSuccess else {
            throw GitHubClientError.gitOperationFailed(reason: "Failed to get current branch")
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Push commits to remote
    /// - Parameter output: Optional client-owned stream to receive output (in addition to global stream)
    public func push(output: CLIOutputStream? = nil) async throws {
        print("\n📤 Pushing commits to remote...")

        let result = try await cliClient.executeForResult(
            Git.Push(),
            workingDirectory: repoPath,
            output: output
        )

        guard result.isSuccess else {
            throw GitHubClientError.gitOperationFailed(reason: "Git push failed: \(result.stderr)")
        }

        print("✅ Commits pushed successfully")
    }

    /// Get repository owner and name from remote URL
    public func getRepoInfo() async throws -> (owner: String, name: String) {
        let result = try await cliClient.executeForResult(
            Git.Config(get: true, key: "remote.origin.url"),
            workingDirectory: repoPath,
            printCommand: false
        )

        guard result.isSuccess else {
            throw GitHubClientError.gitOperationFailed(reason: "Failed to get remote URL")
        }

        let remoteUrl = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse GitHub URL (supports both HTTPS and SSH)
        // https://github.com/owner/repo.git or git@github.com:owner/repo.git
        let pattern = "github\\.com[:/]([^/]+)/([^.]+)(\\.git)?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: remoteUrl, range: NSRange(remoteUrl.startIndex..., in: remoteUrl)),
              match.numberOfRanges >= 3 else {
            throw GitHubClientError.gitOperationFailed(reason: "Could not parse GitHub repository from remote URL: \(remoteUrl)")
        }

        let ownerRange = Range(match.range(at: 1), in: remoteUrl)!
        let nameRange = Range(match.range(at: 2), in: remoteUrl)!

        let owner = String(remoteUrl[ownerRange])
        let name = String(remoteUrl[nameRange])

        return (owner, name)
    }
}
