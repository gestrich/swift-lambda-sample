import Testing
import CLIKit

@Suite("CLIKit Tests")
struct CLIKitTests {

    @Test("String to kebab-case conversion")
    func testKebabCase() {
        #expect(StringUtils.toKebabCase("noFastForward") == "no-fast-forward")
        #expect(StringUtils.toKebabCase("force") == "force")
        #expect(StringUtils.toKebabCase("UpdateIndex") == "update-index")
        #expect(StringUtils.toKebabCase("Git") == "git")
    }

    @Test("CLIFlag components")
    func testFlagComponents() {
        let flag = CLIFlag("--force")
        #expect(flag.components == ["--force"])
    }

    @Test("CLIOption components")
    func testOptionComponents() {
        let option = CLIOption("-m", value: "commit message")
        #expect(option.components == ["-m", "commit message"])
    }

    @Test("CLIPositional components")
    func testPositionalComponents() {
        let positional = CLIPositional("feature-branch")
        #expect(positional.components == ["feature-branch"])
    }

    @Test("CLIArgument enum")
    func testArgumentComponents() {
        let flagArg = CLIArgument.flag(CLIFlag("--force"))
        #expect(flagArg.components == ["--force"])

        let optionArg = CLIArgument.option(CLIOption("-m", value: "message"))
        #expect(optionArg.components == ["-m", "message"])

        let positionalArg = CLIArgument.positional(CLIPositional("branch"))
        #expect(positionalArg.components == ["branch"])
    }
}

@Suite("Git Command Tests")
struct GitCommandTests {

    @Test("Git program name")
    func testProgramName() {
        #expect(Git.programName == "git")
    }

    @Test("Git.Merge command name")
    func testCommandName() {
        #expect(Git.Merge.commandName == "merge")
    }

    @Test("Git.Merge simple usage")
    func testSimpleMerge() {
        let merge = Git.Merge(branch: "feature-branch")
        #expect(merge.commandLine == ["git", "merge", "feature-branch"])
    }

    @Test("Git.Merge with flag")
    func testMergeWithFlag() {
        let merge = Git.Merge(noFastForward: true, branch: "feature-branch")
        #expect(merge.commandLine == ["git", "merge", "--no-fast-forward", "feature-branch"])
    }

    @Test("Git.Merge with message")
    func testMergeWithMessage() {
        let merge = Git.Merge(message: "Merge feature", branch: "feature-branch")
        #expect(merge.commandLine == ["git", "merge", "-m", "Merge feature", "feature-branch"])
    }

    @Test("Git.Merge with all options")
    func testMergeWithAllOptions() {
        let merge = Git.Merge(
            noFastForward: true,
            message: "Merge feature",
            branch: "feature-branch"
        )
        #expect(merge.commandLine == ["git", "merge", "--no-fast-forward", "-m", "Merge feature", "feature-branch"])
    }

    @Test("Git.Merge command string")
    func testMergeCommandString() {
        let merge = Git.Merge(
            noFastForward: true,
            message: "Merge feature",
            branch: "feature-branch"
        )
        #expect(merge.commandString == "git merge --no-fast-forward -m \"Merge feature\" feature-branch")
    }
}
