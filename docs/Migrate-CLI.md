# CLIKit Migration Plan

This document outlines the plan to migrate CLI string-based command execution to use the type-safe CLIKit framework.

## Goals

1. Replace string-based CLI calls with type-safe `@CLIProgram` and `@CLICommand` definitions
2. Centralize standard Unix commands (`ls`, `git`, etc.) in `CLIKit/standard/`
3. Keep project-specific CLI wrappers (`aws`, `cdk`, `gh`, `docker`, etc.) in their respective targets
4. Implement only the commands/options actually used in the codebase
5. Unify MacApp Settings output views into a single view connected to CLIService async sequence

## Migration Process

For each CLI program:
1. Create the `@CLIProgram` struct with `@CLICommand` definitions
2. Add unit tests for the new commands
3. Update the service to use the new typed commands (this is part of step 1 - we create commands and immediately use them)
4. Run tests to verify (`swift test`) but only run the tests for CLIKit. Make sure you can build other targets you cahnged but don't run all their tests as they take too long.
5. Prompt user for approval
6. Mark the checkbox as complete: `- [x]`
7. Commit before moving to the next program

> **Important:** After completing each step, mark it as done by changing `- [ ]` to `- [x]` in this document before committing.

> **Note:** Creating a `@CLIProgram` includes updating the calling service to use the new typed commands. We don't just create the definitions - we integrate them immediately.

---

## CLI Programs to Migrate

### Standard Unix Commands (→ CLIKit/standard/)

- [x] **1. lsof** - Port checking (`lsof -i :PORT`)
  - Files: `XcodeLocalService.swift`, `LinuxLocalService.swift`
  - Commands: `-i` (check port)

- [x] **2. kill** - Process termination (`kill PID`)
  - Files: `XcodeLocalService.swift`
  - Commands: send signal to PID

- [x] **3. id** - User/group ID lookup (`id -u`, `id -g`)
  - Files: `DockerService.swift`
  - Commands: `-u` (user ID), `-g` (group ID)

- [x] **4. rm** - Remove files/directories (`rm -rf`)
  - Files: `LinuxLocalService.swift`
  - Commands: `-rf` (recursive force)

- [x] **5. sh** - Shell execution (`sh -c "command"`)
  - Files: `DockerService.swift`, `XcodeLocalService.swift`
  - Commands: `-c` (execute command string)

### Already in CLIKit/standard/ (Extend as needed)

- [x] **6. Git** - Extend existing `Git.swift`
  - Files: `GitService.swift`
  - Current CLIKit: `Merge`, `Log`, `Status`, `Diff`, `RevList`, `Branch`, `Push`, `Config`
  - Added commands:
    - `Status` (with `--porcelain` flag) - renamed from `StatusPorcelain` to fix command generation
    - `RevList` (with `--count` flag) - for counting commits ahead of upstream
    - `Branch` (with `--show-current` flag) - get current branch name
    - `Push` (with `-u`, remote, branch options) - push to remote
    - `Config` (with `--get` flag) - get config values
  - Added parser: `GitRevListCountParser` for parsing `git rev-list --count` output

### Project-Specific Commands (→ SwiftDeploy target)

- [x] **7. AWS CLI** - AWS operations
  - File: `AWSCLIService.swift`
  - Location: `SwiftDeploy/CLI/Aws.swift`
  - Commands implemented:
    - `CloudFormationDescribeStacks` - `aws cloudformation describe-stacks`
    - `CloudFormationDescribeStackResources` - `aws cloudformation describe-stack-resources`
    - `LambdaUpdateFunctionCode` - `aws lambda update-function-code`
    - `LambdaGetFunction` - `aws lambda get-function`
    - `LogsTail` - `aws logs tail`
    - `S3Ls` - `aws s3 ls`
    - `S3Cp` - `aws s3 cp`
    - `SecretsManagerGetSecretValue` - `aws secretsmanager get-secret-value`
    - `SecretsManagerListSecrets` - `aws secretsmanager list-secrets`
  - Parsers:
    - `CloudFormationStackParser` - Parses stack JSON with outputs
    - `CloudFormationStackResourcesParser` - Parses stack resources JSON
  - Output types:
    - `CloudFormationStack` - Stack status and outputs
    - `CloudFormationStackOutput` - Individual stack output (key, value, description, exportName)
    - `CloudFormationStackResource` - Resource info (logicalResourceId, resourceType, resourceStatus)
  - Technical notes:
    - Multi-word command names (e.g., "cloudformation describe-stacks") are now supported via space-splitting in `CLICommand.commandArguments`
    - `AWSCLIService` maintains aws-vault wrapping support via `buildCommandLine()` method
    - Profile flags are automatically removed when using aws-vault
    - Tests: `Tests/SwiftDeployTests/AWSCLITests.swift` (42 tests)

- [x] **8. CDK** - AWS CDK operations
  - File: `CDKService.swift`
  - Location: `SwiftDeploy/CLI/Cdk.swift`
  - Commands implemented:
    - `Deploy` - deploy with profile, require-approval, context, outputs-file options
    - `Destroy` - destroy with profile, force flag
    - `Diff` - diff with profile
    - `Synth` - synth with profile
    - `List` - list with profile
    - `Bootstrap` - bootstrap with profile
  - Technical notes:
    - Added support for variadic `@Option` (array types) in CLICommandMacro - arrays are automatically detected and expanded to repeated flags (e.g., `--context foo --context bar`)
    - Array options default to empty array `[]` in generated initializer
    - `CDKService` maintains aws-vault wrapping support via `buildCommandLine()` method
    - Profile flags are automatically removed when using aws-vault
  - Tests: `Tests/SwiftDeployTests/CDKTests.swift` (31 tests)

- [x] **9. npm** - Node package manager
  - File: `CDKService.swift`
  - Location: `SwiftDeploy/CLI/Npm.swift`
  - Commands implemented:
    - `Run` - npm run with script positional argument
    - `Install` - npm install with optional package positional argument
  - Tests: `Tests/SwiftDeployTests/NpmTests.swift` (12 tests)

- [x] **10. GitHub CLI (gh)** - GitHub operations
  - File: `GitHubCLIService.swift`
  - Location: `SwiftDeploy/CLI/Gh.swift`
  - Commands implemented:
    - `RunList` - `gh run list` with repo, branch, limit, workflow, json options
    - `RunWatch` - `gh run watch` with optional run ID positional, repo option
    - `RunView` - `gh run view` with run ID positional, repo, log flag
    - `WorkflowRun` - `gh workflow run` with workflow positional, repo, ref options
    - `PrCreate` - `gh pr create` with repo, title, body, base, head options
    - `PrList` - `gh pr list` with repo, state, json, limit options
    - `IssueCreate` - `gh issue create` with repo, title, body options
    - `AuthStatus` - `gh auth status` (no arguments)
  - Output types:
    - `GitHubWorkflowRun` - Workflow run info (databaseId, status, conclusion, createdAt, headBranch, event, displayTitle) with computed `id`, `isCompleted`, `wasSuccessful` properties
    - `GitHubPullRequest` - PR info (number, title, state, headRefName, createdAt)
  - Parsers:
    - `GitHubWorkflowRunsParser` - Parses JSON array of workflow runs
    - `GitHubPullRequestsParser` - Parses JSON array of pull requests
  - Technical notes:
    - Numeric options (limit) must use String type due to CLIKit macro limitation with Int
    - Service converts Int limit parameter to String when building command
    - `GitHubWorkflowRun` includes `id` computed property for backwards compatibility with existing code
    - Uses `executeForResult()` from CLIService to get full ExecutionResult
  - Tests: `Tests/SwiftDeployTests/GitHubCLITests.swift` (45 tests)

- [x] **11. Docker** - Container operations
  - File: `DockerService.swift`
  - Location: `SwiftDeploy/CLI/Docker.swift`
  - Commands implemented:
    - `Info` - `docker info`
    - `Run` - `docker run` with flags: `-d`, `--rm`, `-i`, `-t`, `--platform`, `--name`, `--network`, `-p` (multiple), `-v` (multiple), `-e` (multiple), `--user`, `-w`
    - `Stop` - `docker stop`
    - `Rm` - `docker rm`
    - `Ps` - `docker ps` with flags: `-a`, `--filter` (multiple), `--format`
    - `Logs` - `docker logs` with flags: `-f`, `-t`, `--tail`
    - `Build` - `docker build` with options: `--platform`, `-t`, `-f`, `--build-arg` (multiple), `--secret` (multiple)
    - `NetworkCreate` - `docker network create`
    - `NetworkInspect` - `docker network inspect` with `--format` option
    - `NetworkConnect` - `docker network connect`
  - Output types:
    - `DockerContainer` - Container name from ps command
    - `DockerNetworkContainer` - Container name from network inspect
  - Parsers:
    - `DockerPsNamesParser` - Parses `docker ps --format {{.Names}}` output
    - `DockerNetworkContainersParser` - Parses network inspect container names output
  - Additional:
    - Created `Open` command in `CLIKit/standard/Open.swift` for macOS app launcher (used by `startDockerDesktop()`)
    - Added `inheritIO` parameter to `CLIService.executeForResult()` for typed commands
  - Technical notes:
    - Array options (publish, volume, env, filter, buildArg, secret) use CLIKit's variadic `@Option` support
    - `Docker.Run` supports positional array for command arguments after image
    - `DockerService.build()` uses `commandString` property to wrap in shell command for working directory support
  - Tests: `Tests/SwiftDeployTests/DockerTests.swift` (73 tests)

- [x] **12. Swift** - Swift build operations
  - File: `XcodeLocalService.swift`
  - Location: `SwiftDeploy/CLI/SwiftCLI.swift`
  - Commands implemented:
    - `PackageClean` - `swift package clean`
    - `Build` - `swift build` with `--product` and `--show-bin-path` options
  - Technical notes:
    - Uses `@CLIProgram("swift")` with explicit program name since "SwiftCLI" would convert to "swift-c-l-i" via kebab-case conversion
    - Added generic `stream<C: CLICommand>()` method to CLIService for streaming typed commands
    - Service uses `execute()` for fire-and-forget clean, `stream()` for build output, and `executeForResult()` for getting bin path
  - Tests: `Tests/SwiftDeployTests/SwiftCLITests.swift` (11 tests)

- [x] **13. curl** - HTTP requests
  - Files: `AWSTestingService.swift`, `RemoteService.swift`
  - Location: `SwiftDeploy/CLI/Curl.swift`
  - Commands implemented:
    - `Request` - `curl` with flags: `-X` (method), `-H` (headers, multiple), `-d` (data), `-v` (verbose), `-s` (silent), `-o` (output file), `-w` (write-out format)
  - Convenience initializers:
    - `get(url:silent:verbose:)` - Simple GET request
    - `post(url:data:silent:verbose:)` - Simple POST request
    - `postJSON(url:data:silent:verbose:)` - POST request with JSON Content-Type header
    - `checkStatus(url:)` - Request that returns only HTTP status code (`-s -o /dev/null -w %{http_code}`)
  - Technical notes:
    - Uses empty command name (`@CLICommand("")`) since curl is invoked directly with options
    - Single-character flags require `-` prefix in `@Flag`/`@Option` annotations (e.g., `@Flag("-v")`)
    - Headers option uses array type for multiple `-H` flags
    - URL is a positional argument at the end of command line
  - Tests: `Tests/SwiftDeployTests/CurlTests.swift` (24 tests)

- [x] **14. open** - macOS app launcher
  - File: `DockerService.swift`
  - Location: `CLIKit/standard/Open.swift`
  - Commands implemented:
    - `Open` - with `-a` (application) option and path positional
  - Technical notes:
    - Already implemented during Docker migration (item 11)
    - Used by `DockerService.startDockerDesktop()` to open Docker Desktop
  - Tests: `Tests/CLIKitTests/StandardCommandTests.swift` (OpenCommandTests - 6 tests)

- [x] **15. which** - Command lookup
  - File: `AWSVaultService.swift`
  - Location: `CLIKit/standard/Which.swift`
  - Commands implemented:
    - `Which` - with `-a` (all matches) flag and command positional
  - Technical notes:
    - Used by `AWSVaultService.checkInstallation()` to verify aws-vault is installed
    - Simple `@CLIProgram` with one flag and one positional argument
  - Tests: `Tests/CLIKitTests/StandardCommandTests.swift` (WhichCommandTests - 5 tests)

- [x] **16. Build Script** - Custom build script
  - File: `LinuxLocalService.swift`
  - Location: `SwiftDeploy/CLI/BuildScript.swift`
  - Commands implemented:
    - `Build` - `./build.sh <target> [platform] [githubToken]` with all three positional arguments
  - Convenience initializers:
    - `lambda(target:)` - Simple build for default AWS Lambda platform (linux/amd64)
    - `forPlatform(target:platform:)` - Build with specific platform (e.g., "linux/arm64")
    - `withToken(target:platform:githubToken:)` - Build with GitHub token for private dependencies
  - Technical notes:
    - Uses `@CLIProgram("./build.sh")` with explicit program name for the shell script path
    - Uses `@CLICommand("")` (empty command name) since the script is invoked directly with positional arguments
    - All three arguments (`target`, `platform`, `githubToken`) are positional via `@Positional`
    - `LinuxLocalService.build()` uses `cliService.stream()` for streaming build output to the UI
  - Tests: `Tests/SwiftDeployTests/BuildScriptTests.swift` (15 tests)

---

## MacApp Settings View Update

- [x] **17. Unify Output Views**
  - Previous state: Two separate output views
    - `BuildOutputView` - Shows build streaming output
    - `LambdaOutputView` - Shows Lambda lifecycle output
  - New state: Single unified generic output view
    - `CLIOutputView<State: CLIOutputState>` - Generic view for any CLI output state
    - Type aliases preserve backward compatibility: `BuildOutputView`, `LambdaOutputView`
  - Files created:
    - `Sources/SwiftDeploy/CLIOutputState.swift` - Protocol and status conformances
    - `Sources/MacApp/CLIOutputView.swift` - Unified generic view component
  - Files removed:
    - `Sources/MacApp/BuildOutputView.swift`
    - `Sources/MacApp/LambdaOutputView.swift`
  - Technical notes:
    - Created `CLIOutputStatus` protocol with properties: `isActive`, `iconName`, `displayText`, `colorName`, `showProgress`, `helpText`
    - Created `CLIOutputState` protocol requiring `outputLines`, `status`, and `clear()` method
    - `BuildStatus` and `LambdaStatus` conform to `CLIOutputStatus`
    - `BuildState` and `LambdaState` conform to `CLIOutputState`
    - Generic `CLIOutputView<State: CLIOutputState>` replaces both specific views
    - Type aliases (`BuildOutputView`, `LambdaOutputView`) and convenience initializers maintain API compatibility
    - SettingsView unchanged - uses same initializer syntax via convenience initializers
    - Auto-expand on status change: `onChange(of: state.status.isActive)`

---

## Migration Order

We'll proceed program-by-program in this order:

1. **Standard Unix commands first** (simpler, good warmup)
   - lsof → kill → id → rm → sh

2. **Extend existing Git** (already partially done)
   - Add missing commands to Git.swift

3. **Project-specific commands** (more complex)
   - Swift → npm → curl → open → which
   - AWS CLI → CDK → GitHub CLI → Docker

4. **Build script** (special case)
   - ./build.sh wrapper

5. **MacApp Settings unification** (final step)
   - Unified output view

---

## File Locations Summary

| CLI Program | Location | Notes |
|-------------|----------|-------|
| `Ls` | `CLIKit/standard/Ls.swift` | Already exists |
| `Git` | `CLIKit/standard/Git.swift` | Extend with missing commands |
| `Lsof` | `CLIKit/standard/Lsof.swift` | New - port checking |
| `Kill` | `CLIKit/standard/Kill.swift` | New - process termination |
| `Id` | `CLIKit/standard/Id.swift` | New - user/group ID |
| `Rm` | `CLIKit/standard/Rm.swift` | New - file removal |
| `Sh` | `CLIKit/standard/Sh.swift` | New - shell execution |
| `Which` | `CLIKit/standard/Which.swift` | New - command lookup |
| `Open` | `CLIKit/standard/Open.swift` | New - macOS app launcher |
| `Docker` | `SwiftDeploy/CLI/Docker.swift` | New - Docker |
| `Aws` | `SwiftDeploy/CLI/Aws.swift` | New - AWS CLI |
| `Cdk` | `SwiftDeploy/CLI/Cdk.swift` | New - AWS CDK |
| `Npm` | `SwiftDeploy/CLI/Npm.swift` | New - Node package manager |
| `Gh` | `SwiftDeploy/CLI/Gh.swift` | New - GitHub CLI |
| `Swift` | `SwiftDeploy/CLI/Swift.swift` | New - Swift toolchain |
| `Curl` | `SwiftDeploy/CLI/Curl.swift` | New - HTTP requests |
| `BuildScript` | `SwiftDeploy/CLI/BuildScript.swift` | New - Build script wrapper |
| `CLIOutputState` | `SwiftDeploy/CLIOutputState.swift` | Protocol for unified output views |
| `CLIOutputView` | `MacApp/CLIOutputView.swift` | Unified generic output view |

---

## Testing

Each CLI program/command must have unit tests using the **Swift Testing** framework. Tests verify that `commandLine` output is correct.

### Swift Testing Syntax

```swift
import Testing
import CLIKit

@Suite("Lsof Command Tests")
struct LsofCommandTests {

    @Test("Lsof program name")
    func testProgramName() {
        #expect(Lsof.programName == "lsof")
    }

    @Test("Lsof.CheckPort command line")
    func testCheckPort() {
        let cmd = Lsof.CheckPort(port: 8080)
        #expect(cmd.commandLine == ["lsof", "-i", ":8080"])
    }

    @Test("Lsof.CheckPort with different port")
    func testCheckPortDifferent() {
        let cmd = Lsof.CheckPort(port: 3000)
        #expect(cmd.commandLine == ["lsof", "-i", ":3000"])
    }
}
```

### Key Syntax Elements

| Element | Description | Example |
|---------|-------------|---------|
| `@Suite("Name")` | Groups related tests | `@Suite("Git Command Tests")` |
| `@Test("Description")` | Marks a test function | `@Test("Git.Merge with flag")` |
| `#expect(condition)` | Assert condition is true | `#expect(result == expected)` |
| `#expect(throws:)` | Assert error is thrown | `#expect(throws: Error.self) { ... }` |

### Test File Organization

| CLI Program | Test File |
|-------------|-----------|
| Standard commands | `Tests/CLIKitTests/StandardCommandTests.swift` |
| Git (extended) | `Tests/CLIKitTests/CLIKitTests.swift` (existing) |
| AWS CLI | `Tests/SwiftDeployTests/AWSCLITests.swift` |
| CDK | `Tests/SwiftDeployTests/CDKTests.swift` |
| npm | `Tests/SwiftDeployTests/NpmTests.swift` |
| GitHub CLI | `Tests/SwiftDeployTests/GitHubCLITests.swift` |
| Docker | `Tests/SwiftDeployTests/DockerTests.swift` |
| Swift | `Tests/SwiftDeployTests/SwiftCLITests.swift` |
| curl | `Tests/SwiftDeployTests/CurlTests.swift` |
| BuildScript | `Tests/SwiftDeployTests/BuildScriptTests.swift` |

### Running Tests

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter CLIKitTests

# Run specific test
swift test --filter "Lsof Command Tests"
```

### What to Test

For each `@CLICommand`:
1. **Program name** - `#expect(Program.programName == "expected")`
2. **Command path** - `#expect(Command.commandPath == ["expected", "path"])`
3. **Minimal usage** - Command with only required arguments
4. **With flags** - Command with boolean flags enabled
5. **With options** - Command with optional values provided
6. **Full usage** - Command with all options set
7. **Command string** - Verify `commandString` output for debugging

### References

- [Swift Testing Basics - Donny Wals](https://www.donnywals.com/swift-testing-basics-explained/)
- [Apple Swift Testing Documentation](https://developer.apple.com/documentation/testing)
- [Swift Testing GitHub](https://github.com/swiftlang/swift-testing)

---

## Notes

- Each `@CLIProgram` should implement only the commands/options actually used
- Parsers should be created where structured output is needed
- **Add structured outputs for any command output that has structure** (i.e., not just a single string). If the output contains multiple fields, lists, or parseable data, create a typed output struct and parser.
- Services will be updated to use typed commands instead of string arrays
- The `aws-vault` wrapping pattern in `AWSCLIService` needs special handling
- Docker's `run` command has the most complex option set
- **Imports should be in alphabetical order**
