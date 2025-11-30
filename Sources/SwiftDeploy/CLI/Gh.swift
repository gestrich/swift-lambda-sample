import CLIKit
import Foundation

/// GitHub CLI (gh) program definition using macro-based API
@CLIProgram
public struct Gh {

    // MARK: - Run Commands

    @CLICommand("run")
    public struct Run {
        /// GitHub CLI run list command
        /// Example: gh run list --repo owner/repo --branch dev --limit 5 --json databaseId,status
        @CLICommand("list")
        public struct List {
            /// Repository in owner/repo format
            @Option public var repo: String

            /// Filter by branch name
            @Option public var branch: String?

            /// Maximum number of runs to return
            @Option public var limit: String?

            /// Filter by workflow file name
            @Option public var workflow: String?

            /// JSON fields to output
            @Option public var json: String?
        }

        /// GitHub CLI run watch command
        /// Example: gh run watch 12345 --repo owner/repo
        @CLICommand("watch")
        public struct Watch {
            /// Run ID to watch (optional - watches latest if not provided)
            @Positional public var runId: String?

            /// Repository in owner/repo format
            @Option public var repo: String
        }

        /// GitHub CLI run view command
        /// Example: gh run view 12345 --repo owner/repo --log
        @CLICommand("view")
        public struct View {
            /// Run ID to view
            @Positional public var runId: String

            /// Repository in owner/repo format
            @Option public var repo: String

            /// Show full log output
            @Flag public var log: Bool = false
        }
    }

    // MARK: - Workflow Commands

    @CLICommand("workflow")
    public struct Workflow {
        /// GitHub CLI workflow run command
        /// Example: gh workflow run deploy.yml --repo owner/repo --ref dev
        @CLICommand("run")
        public struct Run {
            /// Workflow file name or ID
            @Positional public var workflow: String

            /// Repository in owner/repo format
            @Option public var repo: String

            /// Git reference (branch, tag, or SHA)
            @Option("--ref") public var ref: String?
        }
    }

    // MARK: - Pull Request Commands

    @CLICommand("pr")
    public struct Pr {
        /// GitHub CLI pr create command
        /// Example: gh pr create --repo owner/repo --title "My PR" --body "Description" --base main --head feature
        @CLICommand("create")
        public struct Create {
            /// Repository in owner/repo format
            @Option public var repo: String

            /// Pull request title
            @Option public var title: String

            /// Pull request body
            @Option public var body: String

            /// Base branch
            @Option public var base: String?

            /// Head branch
            @Option public var head: String?
        }

        /// GitHub CLI pr list command
        /// Example: gh pr list --repo owner/repo --state open --json number,title --limit 10
        @CLICommand("list")
        public struct List {
            /// Repository in owner/repo format
            @Option public var repo: String

            /// State filter (open, closed, merged, all)
            @Option public var state: String?

            /// JSON fields to output
            @Option public var json: String?

            /// Maximum number of PRs to return
            @Option public var limit: String?
        }
    }

    // MARK: - Issue Commands

    @CLICommand("issue")
    public struct Issue {
        /// GitHub CLI issue create command
        /// Example: gh issue create --repo owner/repo --title "Bug" --body "Description"
        @CLICommand("create")
        public struct Create {
            /// Repository in owner/repo format
            @Option public var repo: String

            /// Issue title
            @Option public var title: String

            /// Issue body
            @Option public var body: String
        }
    }

    // MARK: - Auth Commands

    @CLICommand("auth")
    public struct Auth {
        /// GitHub CLI auth status command
        /// Example: gh auth status
        @CLICommand("status")
        public struct Status {
        }
    }
}

// MARK: - Output Types

/// GitHub workflow run information
public struct GitHubWorkflowRun: Sendable, Equatable, Codable {
    public let databaseId: Int
    public let status: String
    public let conclusion: String?
    public let createdAt: String
    public let headBranch: String
    public let event: String
    public let displayTitle: String

    public init(
        databaseId: Int,
        status: String,
        conclusion: String?,
        createdAt: String,
        headBranch: String,
        event: String,
        displayTitle: String
    ) {
        self.databaseId = databaseId
        self.status = status
        self.conclusion = conclusion
        self.createdAt = createdAt
        self.headBranch = headBranch
        self.event = event
        self.displayTitle = displayTitle
    }

    /// String ID for backwards compatibility
    public var id: String {
        String(databaseId)
    }

    /// Whether the run has completed
    public var isCompleted: Bool {
        status == "completed"
    }

    /// Whether the run was successful
    public var wasSuccessful: Bool {
        conclusion == "success"
    }
}

/// GitHub pull request information
public struct GitHubPullRequest: Sendable, Equatable, Codable {
    public let number: Int
    public let title: String
    public let state: String
    public let headRefName: String
    public let createdAt: String

    public init(
        number: Int,
        title: String,
        state: String,
        headRefName: String,
        createdAt: String
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.headRefName = headRefName
        self.createdAt = createdAt
    }
}

// MARK: - Parsers

/// Parser for GitHub workflow runs JSON output
public struct GitHubWorkflowRunsParser: CLIOutputParser {
    public init() {}

    public func parse(_ output: String) throws -> [GitHubWorkflowRun] {
        guard let data = output.data(using: .utf8) else {
            throw CLIServiceError.invalidOutput(reason: "Failed to convert GitHub workflow runs output to data")
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode([GitHubWorkflowRun].self, from: data)
        } catch {
            throw CLIServiceError.invalidOutput(reason: "Failed to parse GitHub workflow runs: \(error)")
        }
    }
}

/// Parser for GitHub pull requests JSON output
public struct GitHubPullRequestsParser: CLIOutputParser {
    public init() {}

    public func parse(_ output: String) throws -> [GitHubPullRequest] {
        guard let data = output.data(using: .utf8) else {
            throw CLIServiceError.invalidOutput(reason: "Failed to convert GitHub pull requests output to data")
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode([GitHubPullRequest].self, from: data)
        } catch {
            throw CLIServiceError.invalidOutput(reason: "Failed to parse GitHub pull requests: \(error)")
        }
    }
}
