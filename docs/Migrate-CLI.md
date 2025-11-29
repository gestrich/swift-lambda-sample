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
4. Run tests to verify (`swift test`)
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

- [ ] **8. CDK** - AWS CDK operations
  - File: `CDKService.swift`
  - Commands:
    - `deploy` (with `--context` flags)
    - `destroy`
    - `diff`
    - `synth`
    - `list`
    - `bootstrap`

- [ ] **9. npm** - Node package manager
  - File: `CDKService.swift`
  - Commands:
    - `run build`
    - `install`

- [ ] **10. GitHub CLI (gh)** - GitHub operations
  - File: `GitHubCLIService.swift`
  - Commands:
    - `run list`
    - `run watch`
    - `run view`
    - `workflow run`
    - `pr create`
    - `pr list`
    - `issue create`
    - `auth status`

- [ ] **11. Docker** - Container operations
  - File: `DockerService.swift`
  - Commands:
    - `info`
    - `run` (complex with many options: `-d`, `--rm`, `-i`, `-t`, `--platform`, `--name`, `--network`, `-p`, `-v`, `-e`, `--user`, `-w`)
    - `stop`
    - `rm`
    - `ps`
    - `build`
    - `network create`
    - `network inspect`
    - `network connect`
    - `logs`

- [ ] **12. Swift** - Swift build operations
  - File: `XcodeLocalService.swift`
  - Commands:
    - `package clean`
    - `build --product`
    - `build --show-bin-path`

- [ ] **13. curl** - HTTP requests
  - Files: `AWSTestingService.swift`, `RemoteService.swift`
  - Commands:
    - `-X POST/GET`
    - `-H` (headers)
    - `-d` (data)
    - `-v` (verbose)
    - `-s` (silent)
    - `-o /dev/null`
    - `-w %{http_code}`

- [ ] **14. open** - macOS app launcher
  - File: `DockerService.swift`
  - Commands:
    - `-a Docker` (open Docker Desktop)

- [ ] **15. which** - Command lookup
  - File: `AWSVaultService.swift`
  - Commands:
    - Check if command exists

- [ ] **16. Build Script** - Custom build script
  - File: `LinuxLocalService.swift`
  - Commands:
    - `./build.sh SwiftLambda`

---

## MacApp Settings View Update

- [ ] **17. Unify Output Views**
  - Current state: Two separate output views
    - `BuildOutputView` - Shows build streaming output
    - `LambdaOutputView` - Shows Lambda lifecycle output
  - Target state: Single unified output view
    - Connect to CLIService async sequence
    - All CLI operations stream to the same view
    - Remove duplicate views from Settings
  - Implementation:
    - Add AsyncSequence support to CLIService for global output streaming
    - Create unified `CLIOutputView` component
    - Update `SettingsView` to use single output view
    - Remove `BuildOutputView` and `LambdaOutputView`

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
| `Aws` | `SwiftDeploy/CLI/Aws.swift` | New - AWS CLI |
| `Cdk` | `SwiftDeploy/CLI/Cdk.swift` | New - AWS CDK |
| `Npm` | `SwiftDeploy/CLI/Npm.swift` | New - Node package manager |
| `Gh` | `SwiftDeploy/CLI/Gh.swift` | New - GitHub CLI |
| `Docker` | `SwiftDeploy/CLI/Docker.swift` | New - Docker |
| `Swift` | `SwiftDeploy/CLI/Swift.swift` | New - Swift toolchain |
| `Curl` | `SwiftDeploy/CLI/Curl.swift` | New - HTTP requests |

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
2. **Command name** - `#expect(Command.commandName == "expected")`
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
