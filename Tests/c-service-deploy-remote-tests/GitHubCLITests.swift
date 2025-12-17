import CLISDK
import GitHubSDK
@testable import c_service_deploy_remote
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

    @Test("Run.List commandPath")
    func testCommandPath() {
        #expect(Gh.Run.List.commandPath == ["run", "list"])
    }

    @Test("Run.List minimal command line")
    func testMinimalCommandLine() {
        let cmd = Gh.Run.List(repo: "owner/repo")
        #expect(cmd.commandLine == [
            "gh", "run", "list",
            "--repo", "owner/repo"
        ])
    }

    @Test("Run.List with branch")
    func testWithBranch() {
        let cmd = Gh.Run.List(repo: "owner/repo", branch: "dev")
        #expect(cmd.commandLine == [
            "gh", "run", "list",
            "--repo", "owner/repo",
            "--branch", "dev"
        ])
    }

    @Test("Run.List with limit")
    func testWithLimit() {
        let cmd = Gh.Run.List(repo: "owner/repo", limit: "5")
        #expect(cmd.commandLine == [
            "gh", "run", "list",
            "--repo", "owner/repo",
            "--limit", "5"
        ])
    }

    @Test("Run.List with workflow")
    func testWithWorkflow() {
        let cmd = Gh.Run.List(repo: "owner/repo", workflow: "deploy.yml")
        #expect(cmd.commandLine == [
            "gh", "run", "list",
            "--repo", "owner/repo",
            "--workflow", "deploy.yml"
        ])
    }

    @Test("Run.List with JSON fields")
    func testWithJson() {
        let cmd = Gh.Run.List(repo: "owner/repo", json: "databaseId,status,conclusion")
        #expect(cmd.commandLine == [
            "gh", "run", "list",
            "--repo", "owner/repo",
            "--json", "databaseId,status,conclusion"
        ])
    }

    @Test("Run.List with all options")
    func testWithAllOptions() {
        let cmd = Gh.Run.List(
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

    @Test("Run.List command string")
    func testCommandString() {
        let cmd = Gh.Run.List(repo: "owner/repo", branch: "dev", limit: "5")
        #expect(cmd.commandString == "gh run list --repo owner/repo --branch dev --limit 5")
    }
}

@Suite("Run Watch Tests")
struct RunWatchTests {

    @Test("Run.Watch commandPath")
    func testCommandPath() {
        #expect(Gh.Run.Watch.commandPath == ["run", "watch"])
    }

    @Test("Run.Watch minimal command line")
    func testMinimalCommandLine() {
        let cmd = Gh.Run.Watch(repo: "owner/repo")
        #expect(cmd.commandLine == [
            "gh", "run", "watch",
            "--repo", "owner/repo"
        ])
    }

    @Test("Run.Watch with run ID")
    func testWithRunId() {
        let cmd = Gh.Run.Watch(runId: "12345", repo: "owner/repo")
        #expect(cmd.commandLine == [
            "gh", "run", "watch",
            "12345",
            "--repo", "owner/repo"
        ])
    }

    @Test("Run.Watch command string")
    func testCommandString() {
        let cmd = Gh.Run.Watch(runId: "12345", repo: "owner/repo")
        #expect(cmd.commandString == "gh run watch 12345 --repo owner/repo")
    }
}

@Suite("Run View Tests")
struct RunViewTests {

    @Test("Run.View commandPath")
    func testCommandPath() {
        #expect(Gh.Run.View.commandPath == ["run", "view"])
    }

    @Test("Run.View minimal command line")
    func testMinimalCommandLine() {
        let cmd = Gh.Run.View(runId: "12345", repo: "owner/repo")
        #expect(cmd.commandLine == [
            "gh", "run", "view",
            "12345",
            "--repo", "owner/repo"
        ])
    }

    @Test("Run.View with log flag")
    func testWithLogFlag() {
        let cmd = Gh.Run.View(runId: "12345", repo: "owner/repo", log: true)
        #expect(cmd.commandLine == [
            "gh", "run", "view",
            "12345",
            "--repo", "owner/repo",
            "--log"
        ])
    }

    @Test("Run.View command string")
    func testCommandString() {
        let cmd = Gh.Run.View(runId: "12345", repo: "owner/repo", log: true)
        #expect(cmd.commandString == "gh run view 12345 --repo owner/repo --log")
    }
}

// MARK: - Workflow Commands

@Suite("Workflow Run Tests")
struct WorkflowRunTests {

    @Test("Workflow.Run commandPath")
    func testCommandPath() {
        #expect(Gh.Workflow.Run.commandPath == ["workflow", "run"])
    }

    @Test("Workflow.Run minimal command line")
    func testMinimalCommandLine() {
        let cmd = Gh.Workflow.Run(workflow: "deploy.yml", repo: "owner/repo")
        #expect(cmd.commandLine == [
            "gh", "workflow", "run",
            "deploy.yml",
            "--repo", "owner/repo"
        ])
    }

    @Test("Workflow.Run with ref")
    func testWithRef() {
        let cmd = Gh.Workflow.Run(workflow: "deploy.yml", repo: "owner/repo", ref: "dev")
        #expect(cmd.commandLine == [
            "gh", "workflow", "run",
            "deploy.yml",
            "--repo", "owner/repo",
            "--ref", "dev"
        ])
    }

    @Test("Workflow.Run command string")
    func testCommandString() {
        let cmd = Gh.Workflow.Run(workflow: "deploy.yml", repo: "owner/repo", ref: "main")
        #expect(cmd.commandString == "gh workflow run deploy.yml --repo owner/repo --ref main")
    }
}

// MARK: - Pull Request Commands

@Suite("PR Create Tests")
struct PrCreateTests {

    @Test("Pr.Create commandPath")
    func testCommandPath() {
        #expect(Gh.Pr.Create.commandPath == ["pr", "create"])
    }

    @Test("Pr.Create minimal command line")
    func testMinimalCommandLine() {
        let cmd = Gh.Pr.Create(repo: "owner/repo", title: "My PR", body: "Description")
        #expect(cmd.commandLine == [
            "gh", "pr", "create",
            "--repo", "owner/repo",
            "--title", "My PR",
            "--body", "Description"
        ])
    }

    @Test("Pr.Create with base branch")
    func testWithBaseBranch() {
        let cmd = Gh.Pr.Create(
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

    @Test("Pr.Create with head branch")
    func testWithHeadBranch() {
        let cmd = Gh.Pr.Create(
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

    @Test("Pr.Create with all options")
    func testWithAllOptions() {
        let cmd = Gh.Pr.Create(
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

    @Test("Pr.Create command string")
    func testCommandString() {
        let cmd = Gh.Pr.Create(repo: "owner/repo", title: "My PR", body: "Description")
        #expect(cmd.commandString == "gh pr create --repo owner/repo --title \"My PR\" --body Description")
    }
}

@Suite("PR List Tests")
struct PrListTests {

    @Test("Pr.List commandPath")
    func testCommandPath() {
        #expect(Gh.Pr.List.commandPath == ["pr", "list"])
    }

    @Test("Pr.List minimal command line")
    func testMinimalCommandLine() {
        let cmd = Gh.Pr.List(repo: "owner/repo")
        #expect(cmd.commandLine == [
            "gh", "pr", "list",
            "--repo", "owner/repo"
        ])
    }

    @Test("Pr.List with state")
    func testWithState() {
        let cmd = Gh.Pr.List(repo: "owner/repo", state: "open")
        #expect(cmd.commandLine == [
            "gh", "pr", "list",
            "--repo", "owner/repo",
            "--state", "open"
        ])
    }

    @Test("Pr.List with JSON fields")
    func testWithJson() {
        let cmd = Gh.Pr.List(repo: "owner/repo", json: "number,title,state")
        #expect(cmd.commandLine == [
            "gh", "pr", "list",
            "--repo", "owner/repo",
            "--json", "number,title,state"
        ])
    }

    @Test("Pr.List with limit")
    func testWithLimit() {
        let cmd = Gh.Pr.List(repo: "owner/repo", limit: "10")
        #expect(cmd.commandLine == [
            "gh", "pr", "list",
            "--repo", "owner/repo",
            "--limit", "10"
        ])
    }

    @Test("Pr.List with all options")
    func testWithAllOptions() {
        let cmd = Gh.Pr.List(
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

    @Test("Pr.List command string")
    func testCommandString() {
        let cmd = Gh.Pr.List(repo: "owner/repo", state: "open", limit: "5")
        #expect(cmd.commandString == "gh pr list --repo owner/repo --state open --limit 5")
    }
}

// MARK: - Issue Commands

@Suite("Issue Create Tests")
struct IssueCreateTests {

    @Test("Issue.Create commandPath")
    func testCommandPath() {
        #expect(Gh.Issue.Create.commandPath == ["issue", "create"])
    }

    @Test("Issue.Create command line")
    func testCommandLine() {
        let cmd = Gh.Issue.Create(repo: "owner/repo", title: "Bug Report", body: "Description of bug")
        #expect(cmd.commandLine == [
            "gh", "issue", "create",
            "--repo", "owner/repo",
            "--title", "Bug Report",
            "--body", "Description of bug"
        ])
    }

    @Test("Issue.Create command string")
    func testCommandString() {
        let cmd = Gh.Issue.Create(repo: "owner/repo", title: "Bug", body: "Details")
        #expect(cmd.commandString == "gh issue create --repo owner/repo --title Bug --body Details")
    }
}

// MARK: - Auth Commands

@Suite("Auth Status Tests")
struct AuthStatusTests {

    @Test("Auth.Status commandPath")
    func testCommandPath() {
        #expect(Gh.Auth.Status.commandPath == ["auth", "status"])
    }

    @Test("Auth.Status command line")
    func testCommandLine() {
        let cmd = Gh.Auth.Status()
        #expect(cmd.commandLine == [
            "gh", "auth", "status"
        ])
    }

    @Test("Auth.Status command string")
    func testCommandString() {
        let cmd = Gh.Auth.Status()
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
