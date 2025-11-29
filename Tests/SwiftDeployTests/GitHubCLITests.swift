import CLIKit
@testable import SwiftDeploy
import Testing

@Suite("GitHub CLI Command Tests")
struct GitHubCLITests {

    @Test("Gh program name")
    func testProgramName() {
        #expect(Gh.programName == "gh")
    }
}

// MARK: - Run Commands

@Suite("Run List Tests")
struct RunListTests {

    @Test("RunList command name")
    func testCommandName() {
        #expect(Gh.RunList.commandName == "run list")
    }

    @Test("RunList minimal command line")
    func testMinimalCommandLine() {
        let cmd = Gh.RunList(repo: "owner/repo")
        #expect(cmd.commandLine == [
            "gh", "run", "list",
            "--repo", "owner/repo"
        ])
    }

    @Test("RunList with branch")
    func testWithBranch() {
        let cmd = Gh.RunList(repo: "owner/repo", branch: "dev")
        #expect(cmd.commandLine == [
            "gh", "run", "list",
            "--repo", "owner/repo",
            "--branch", "dev"
        ])
    }

    @Test("RunList with limit")
    func testWithLimit() {
        let cmd = Gh.RunList(repo: "owner/repo", limit: "5")
        #expect(cmd.commandLine == [
            "gh", "run", "list",
            "--repo", "owner/repo",
            "--limit", "5"
        ])
    }

    @Test("RunList with workflow")
    func testWithWorkflow() {
        let cmd = Gh.RunList(repo: "owner/repo", workflow: "deploy.yml")
        #expect(cmd.commandLine == [
            "gh", "run", "list",
            "--repo", "owner/repo",
            "--workflow", "deploy.yml"
        ])
    }

    @Test("RunList with JSON fields")
    func testWithJson() {
        let cmd = Gh.RunList(repo: "owner/repo", json: "databaseId,status,conclusion")
        #expect(cmd.commandLine == [
            "gh", "run", "list",
            "--repo", "owner/repo",
            "--json", "databaseId,status,conclusion"
        ])
    }

    @Test("RunList with all options")
    func testWithAllOptions() {
        let cmd = Gh.RunList(
            repo: "owner/repo",
            branch: "main",
            limit: "10",
            workflow: "ci.yml",
            json: "databaseId,status"
        )
        #expect(cmd.commandLine == [
            "gh", "run", "list",
            "--repo", "owner/repo",
            "--branch", "main",
            "--limit", "10",
            "--workflow", "ci.yml",
            "--json", "databaseId,status"
        ])
    }

    @Test("RunList command string")
    func testCommandString() {
        let cmd = Gh.RunList(repo: "owner/repo", branch: "dev", limit: "5")
        #expect(cmd.commandString == "gh run list --repo owner/repo --branch dev --limit 5")
    }
}

@Suite("Run Watch Tests")
struct RunWatchTests {

    @Test("RunWatch command name")
    func testCommandName() {
        #expect(Gh.RunWatch.commandName == "run watch")
    }

    @Test("RunWatch minimal command line")
    func testMinimalCommandLine() {
        let cmd = Gh.RunWatch(repo: "owner/repo")
        #expect(cmd.commandLine == [
            "gh", "run", "watch",
            "--repo", "owner/repo"
        ])
    }

    @Test("RunWatch with run ID")
    func testWithRunId() {
        let cmd = Gh.RunWatch(runId: "12345", repo: "owner/repo")
        #expect(cmd.commandLine == [
            "gh", "run", "watch",
            "12345",
            "--repo", "owner/repo"
        ])
    }

    @Test("RunWatch command string")
    func testCommandString() {
        let cmd = Gh.RunWatch(runId: "12345", repo: "owner/repo")
        #expect(cmd.commandString == "gh run watch 12345 --repo owner/repo")
    }
}

@Suite("Run View Tests")
struct RunViewTests {

    @Test("RunView command name")
    func testCommandName() {
        #expect(Gh.RunView.commandName == "run view")
    }

    @Test("RunView minimal command line")
    func testMinimalCommandLine() {
        let cmd = Gh.RunView(runId: "12345", repo: "owner/repo")
        #expect(cmd.commandLine == [
            "gh", "run", "view",
            "12345",
            "--repo", "owner/repo"
        ])
    }

    @Test("RunView with log flag")
    func testWithLogFlag() {
        let cmd = Gh.RunView(runId: "12345", repo: "owner/repo", log: true)
        #expect(cmd.commandLine == [
            "gh", "run", "view",
            "12345",
            "--repo", "owner/repo",
            "--log"
        ])
    }

    @Test("RunView command string")
    func testCommandString() {
        let cmd = Gh.RunView(runId: "12345", repo: "owner/repo", log: true)
        #expect(cmd.commandString == "gh run view 12345 --repo owner/repo --log")
    }
}

// MARK: - Workflow Commands

@Suite("Workflow Run Tests")
struct WorkflowRunTests {

    @Test("WorkflowRun command name")
    func testCommandName() {
        #expect(Gh.WorkflowRun.commandName == "workflow run")
    }

    @Test("WorkflowRun minimal command line")
    func testMinimalCommandLine() {
        let cmd = Gh.WorkflowRun(workflow: "deploy.yml", repo: "owner/repo")
        #expect(cmd.commandLine == [
            "gh", "workflow", "run",
            "deploy.yml",
            "--repo", "owner/repo"
        ])
    }

    @Test("WorkflowRun with ref")
    func testWithRef() {
        let cmd = Gh.WorkflowRun(workflow: "deploy.yml", repo: "owner/repo", ref: "dev")
        #expect(cmd.commandLine == [
            "gh", "workflow", "run",
            "deploy.yml",
            "--repo", "owner/repo",
            "--ref", "dev"
        ])
    }

    @Test("WorkflowRun command string")
    func testCommandString() {
        let cmd = Gh.WorkflowRun(workflow: "deploy.yml", repo: "owner/repo", ref: "main")
        #expect(cmd.commandString == "gh workflow run deploy.yml --repo owner/repo --ref main")
    }
}

// MARK: - Pull Request Commands

@Suite("PR Create Tests")
struct PrCreateTests {

    @Test("PrCreate command name")
    func testCommandName() {
        #expect(Gh.PrCreate.commandName == "pr create")
    }

    @Test("PrCreate minimal command line")
    func testMinimalCommandLine() {
        let cmd = Gh.PrCreate(repo: "owner/repo", title: "My PR", body: "Description")
        #expect(cmd.commandLine == [
            "gh", "pr", "create",
            "--repo", "owner/repo",
            "--title", "My PR",
            "--body", "Description"
        ])
    }

    @Test("PrCreate with base branch")
    func testWithBaseBranch() {
        let cmd = Gh.PrCreate(
            repo: "owner/repo",
            title: "My PR",
            body: "Description",
            base: "main"
        )
        #expect(cmd.commandLine == [
            "gh", "pr", "create",
            "--repo", "owner/repo",
            "--title", "My PR",
            "--body", "Description",
            "--base", "main"
        ])
    }

    @Test("PrCreate with head branch")
    func testWithHeadBranch() {
        let cmd = Gh.PrCreate(
            repo: "owner/repo",
            title: "My PR",
            body: "Description",
            head: "feature-branch"
        )
        #expect(cmd.commandLine == [
            "gh", "pr", "create",
            "--repo", "owner/repo",
            "--title", "My PR",
            "--body", "Description",
            "--head", "feature-branch"
        ])
    }

    @Test("PrCreate with all options")
    func testWithAllOptions() {
        let cmd = Gh.PrCreate(
            repo: "owner/repo",
            title: "My PR",
            body: "Description",
            base: "main",
            head: "feature-branch"
        )
        #expect(cmd.commandLine == [
            "gh", "pr", "create",
            "--repo", "owner/repo",
            "--title", "My PR",
            "--body", "Description",
            "--base", "main",
            "--head", "feature-branch"
        ])
    }

    @Test("PrCreate command string")
    func testCommandString() {
        let cmd = Gh.PrCreate(repo: "owner/repo", title: "My PR", body: "Description")
        #expect(cmd.commandString == "gh pr create --repo owner/repo --title \"My PR\" --body Description")
    }
}

@Suite("PR List Tests")
struct PrListTests {

    @Test("PrList command name")
    func testCommandName() {
        #expect(Gh.PrList.commandName == "pr list")
    }

    @Test("PrList minimal command line")
    func testMinimalCommandLine() {
        let cmd = Gh.PrList(repo: "owner/repo")
        #expect(cmd.commandLine == [
            "gh", "pr", "list",
            "--repo", "owner/repo"
        ])
    }

    @Test("PrList with state")
    func testWithState() {
        let cmd = Gh.PrList(repo: "owner/repo", state: "open")
        #expect(cmd.commandLine == [
            "gh", "pr", "list",
            "--repo", "owner/repo",
            "--state", "open"
        ])
    }

    @Test("PrList with JSON fields")
    func testWithJson() {
        let cmd = Gh.PrList(repo: "owner/repo", json: "number,title,state")
        #expect(cmd.commandLine == [
            "gh", "pr", "list",
            "--repo", "owner/repo",
            "--json", "number,title,state"
        ])
    }

    @Test("PrList with limit")
    func testWithLimit() {
        let cmd = Gh.PrList(repo: "owner/repo", limit: "10")
        #expect(cmd.commandLine == [
            "gh", "pr", "list",
            "--repo", "owner/repo",
            "--limit", "10"
        ])
    }

    @Test("PrList with all options")
    func testWithAllOptions() {
        let cmd = Gh.PrList(
            repo: "owner/repo",
            state: "closed",
            json: "number,title",
            limit: "20"
        )
        #expect(cmd.commandLine == [
            "gh", "pr", "list",
            "--repo", "owner/repo",
            "--state", "closed",
            "--json", "number,title",
            "--limit", "20"
        ])
    }

    @Test("PrList command string")
    func testCommandString() {
        let cmd = Gh.PrList(repo: "owner/repo", state: "open", limit: "5")
        #expect(cmd.commandString == "gh pr list --repo owner/repo --state open --limit 5")
    }
}

// MARK: - Issue Commands

@Suite("Issue Create Tests")
struct IssueCreateTests {

    @Test("IssueCreate command name")
    func testCommandName() {
        #expect(Gh.IssueCreate.commandName == "issue create")
    }

    @Test("IssueCreate command line")
    func testCommandLine() {
        let cmd = Gh.IssueCreate(repo: "owner/repo", title: "Bug Report", body: "Description of bug")
        #expect(cmd.commandLine == [
            "gh", "issue", "create",
            "--repo", "owner/repo",
            "--title", "Bug Report",
            "--body", "Description of bug"
        ])
    }

    @Test("IssueCreate command string")
    func testCommandString() {
        let cmd = Gh.IssueCreate(repo: "owner/repo", title: "Bug", body: "Details")
        #expect(cmd.commandString == "gh issue create --repo owner/repo --title Bug --body Details")
    }
}

// MARK: - Auth Commands

@Suite("Auth Status Tests")
struct AuthStatusTests {

    @Test("AuthStatus command name")
    func testCommandName() {
        #expect(Gh.AuthStatus.commandName == "auth status")
    }

    @Test("AuthStatus command line")
    func testCommandLine() {
        let cmd = Gh.AuthStatus()
        #expect(cmd.commandLine == [
            "gh", "auth", "status"
        ])
    }

    @Test("AuthStatus command string")
    func testCommandString() {
        let cmd = Gh.AuthStatus()
        #expect(cmd.commandString == "gh auth status")
    }
}

// MARK: - Parser Tests

@Suite("GitHub Workflow Runs Parser Tests")
struct GitHubWorkflowRunsParserTests {

    @Test("Parse workflow runs JSON")
    func testParseWorkflowRuns() throws {
        let parser = GitHubWorkflowRunsParser()
        let json = """
        [
            {
                "databaseId": 12345,
                "status": "completed",
                "conclusion": "success",
                "createdAt": "2024-01-15T10:30:00Z",
                "headBranch": "dev",
                "event": "push",
                "displayTitle": "Deploy to production"
            },
            {
                "databaseId": 12344,
                "status": "completed",
                "conclusion": "failure",
                "createdAt": "2024-01-15T09:00:00Z",
                "headBranch": "main",
                "event": "pull_request",
                "displayTitle": "Fix bug"
            }
        ]
        """

        let runs = try parser.parse(json)
        #expect(runs.count == 2)
        #expect(runs[0].databaseId == 12345)
        #expect(runs[0].status == "completed")
        #expect(runs[0].conclusion == "success")
        #expect(runs[0].headBranch == "dev")
        #expect(runs[0].isCompleted == true)
        #expect(runs[0].wasSuccessful == true)
        #expect(runs[1].databaseId == 12344)
        #expect(runs[1].conclusion == "failure")
        #expect(runs[1].wasSuccessful == false)
    }

    @Test("Parse workflow run with null conclusion")
    func testParseInProgressRun() throws {
        let parser = GitHubWorkflowRunsParser()
        let json = """
        [
            {
                "databaseId": 12346,
                "status": "in_progress",
                "conclusion": null,
                "createdAt": "2024-01-15T11:00:00Z",
                "headBranch": "feature",
                "event": "push",
                "displayTitle": "Running tests"
            }
        ]
        """

        let runs = try parser.parse(json)
        #expect(runs.count == 1)
        #expect(runs[0].status == "in_progress")
        #expect(runs[0].conclusion == nil)
        #expect(runs[0].isCompleted == false)
        #expect(runs[0].wasSuccessful == false)
    }

    @Test("Parse empty array")
    func testParseEmptyArray() throws {
        let parser = GitHubWorkflowRunsParser()
        let runs = try parser.parse("[]")
        #expect(runs.isEmpty)
    }
}

@Suite("GitHub Pull Requests Parser Tests")
struct GitHubPullRequestsParserTests {

    @Test("Parse pull requests JSON")
    func testParsePullRequests() throws {
        let parser = GitHubPullRequestsParser()
        let json = """
        [
            {
                "number": 123,
                "title": "Add new feature",
                "state": "open",
                "headRefName": "feature-branch",
                "createdAt": "2024-01-15T10:30:00Z"
            },
            {
                "number": 122,
                "title": "Fix bug",
                "state": "closed",
                "headRefName": "bugfix",
                "createdAt": "2024-01-14T09:00:00Z"
            }
        ]
        """

        let prs = try parser.parse(json)
        #expect(prs.count == 2)
        #expect(prs[0].number == 123)
        #expect(prs[0].title == "Add new feature")
        #expect(prs[0].state == "open")
        #expect(prs[0].headRefName == "feature-branch")
        #expect(prs[1].number == 122)
        #expect(prs[1].state == "closed")
    }

    @Test("Parse empty array")
    func testParseEmptyArray() throws {
        let parser = GitHubPullRequestsParser()
        let prs = try parser.parse("[]")
        #expect(prs.isEmpty)
    }
}
