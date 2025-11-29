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

    @Test("CLIPrefixOption components")
    func testPrefixOptionComponents() {
        let prefixOption = CLIPrefixOption("-", value: "9")
        #expect(prefixOption.components == ["-9"])

        let termOption = CLIPrefixOption("-", value: "TERM")
        #expect(termOption.components == ["-TERM"])
    }

    @Test("CLIArgument enum")
    func testArgumentComponents() {
        let flagArg = CLIArgument.flag(CLIFlag("--force"))
        #expect(flagArg.components == ["--force"])

        let optionArg = CLIArgument.option(CLIOption("-m", value: "message"))
        #expect(optionArg.components == ["-m", "message"])

        let prefixOptionArg = CLIArgument.prefixOption(CLIPrefixOption("-", value: "9"))
        #expect(prefixOptionArg.components == ["-9"])

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

    @Test("Git.Log command line")
    func testLogCommandLine() {
        let log = Git.Log()
        #expect(log.commandLine == ["git", "log", "--format", "%H|%an|%ae|%s|%aI"])
    }

    @Test("Git.Log with maxCount")
    func testLogWithMaxCount() {
        let log = Git.Log(maxCount: "5")
        #expect(log.commandLine == ["git", "log", "--format", "%H|%an|%ae|%s|%aI", "-n", "5"])
    }

    @Test("Git.StatusPorcelain command line")
    func testStatusPorcelainCommandLine() {
        let status = Git.StatusPorcelain()
        #expect(status.commandLine == ["git", "status-porcelain", "--porcelain"])
    }
}

@Suite("Parser Tests")
struct ParserTests {

    @Test("GitLogParser parses commits")
    func testLogParse() throws {
        let parser = GitLogParser()
        let output = """
        abc123|John Doe|john@example.com|Initial commit|2025-01-15T10:30:00Z
        def456|Jane Smith|jane@example.com|Add feature|2025-01-16T14:20:00Z
        """

        let commits = try parser.parse(output)

        #expect(commits.count == 2)
        #expect(commits[0].hash == "abc123")
        #expect(commits[0].authorName == "John Doe")
        #expect(commits[0].authorEmail == "john@example.com")
        #expect(commits[0].subject == "Initial commit")
        #expect(commits[1].hash == "def456")
        #expect(commits[1].authorName == "Jane Smith")
    }

    @Test("GitLogParser handles empty output")
    func testLogParseEmpty() throws {
        let parser = GitLogParser()
        let commits = try parser.parse("")
        #expect(commits.isEmpty)
    }

    @Test("GitLogParser throws on invalid format")
    func testLogParseInvalid() {
        let parser = GitLogParser()
        #expect(throws: CLIServiceError.self) {
            _ = try parser.parse("invalid|only|three")
        }
    }

    @Test("GitStatusParser parses staged files")
    func testStatusPorcelainStaged() throws {
        let parser = GitStatusParser()
        let output = """
        M  file1.swift
        A  file2.swift
        """

        let result = try parser.parse(output)

        #expect(result.staged.count == 2)
        #expect(result.staged[0].status == "M")
        #expect(result.staged[0].path == "file1.swift")
        #expect(result.staged[1].status == "A")
        #expect(result.staged[1].path == "file2.swift")
        #expect(result.unstaged.isEmpty)
        #expect(result.untracked.isEmpty)
    }

    @Test("GitStatusParser parses unstaged files")
    func testStatusPorcelainUnstaged() throws {
        let parser = GitStatusParser()
        let output = " M file1.swift\n D file2.swift"

        let result = try parser.parse(output)

        #expect(result.staged.isEmpty)
        #expect(result.unstaged.count == 2)
        #expect(result.unstaged[0].status == "M")
        #expect(result.unstaged[1].status == "D")
    }

    @Test("GitStatusParser parses untracked files")
    func testStatusPorcelainUntracked() throws {
        let parser = GitStatusParser()
        let output = "?? newfile.swift\n?? another.swift"

        let result = try parser.parse(output)

        #expect(result.staged.isEmpty)
        #expect(result.unstaged.isEmpty)
        #expect(result.untracked.count == 2)
        #expect(result.untracked[0] == "newfile.swift")
        #expect(result.untracked[1] == "another.swift")
    }

    @Test("GitStatusParser hasChanges and isClean")
    func testStatusPorcelainHelpers() throws {
        let parser = GitStatusParser()

        let clean = try parser.parse("")
        #expect(clean.isClean)
        #expect(!clean.hasChanges)

        let dirty = try parser.parse("M  file.swift")
        #expect(!dirty.isClean)
        #expect(dirty.hasChanges)
    }

    @Test("GitFileChange statusDescription")
    func testFileChangeDescription() {
        #expect(GitFileChange(status: "M", path: "").statusDescription == "modified")
        #expect(GitFileChange(status: "A", path: "").statusDescription == "added")
        #expect(GitFileChange(status: "D", path: "").statusDescription == "deleted")
        #expect(GitFileChange(status: "R", path: "").statusDescription == "renamed")
        #expect(GitFileChange(status: "C", path: "").statusDescription == "copied")
        #expect(GitFileChange(status: "U", path: "").statusDescription == "unmerged")
        #expect(GitFileChange(status: "X", path: "").statusDescription == "unknown")
    }
}

@Suite("CLIOutputParser Tests")
struct CLIOutputParserTests {

    @Test("StringParser trims whitespace")
    func testStringParser() {
        let parser = StringParser()
        #expect(parser.parse("  hello world  \n") == "hello world")
    }

    @Test("LinesParser splits into lines")
    func testLinesParser() {
        let parser = LinesParser()
        let result = parser.parse("line1\nline2\n\nline3\n")
        #expect(result == ["line1", "line2", "", "line3", ""])
    }

    @Test("LinesParser handles empty input")
    func testLinesParserEmpty() {
        let parser = LinesParser()
        let result = parser.parse("")
        #expect(result == [""])
    }

    @Test("JSONOutputParser decodes valid JSON")
    func testJSONParser() throws {
        struct TestData: Decodable, Sendable, Equatable {
            let name: String
            let count: Int
        }

        let parser = JSONOutputParser<TestData>()
        let result = try parser.parse(#"{"name": "test", "count": 42}"#)
        #expect(result == TestData(name: "test", count: 42))
    }

    @Test("JSONOutputParser decodes arrays")
    func testJSONParserArray() throws {
        let parser = JSONOutputParser<[String]>()
        let result = try parser.parse(#"["a", "b", "c"]"#)
        #expect(result == ["a", "b", "c"])
    }

    @Test("JSONOutputParser throws on invalid JSON")
    func testJSONParserInvalid() {
        let parser = JSONOutputParser<[String]>()
        #expect(throws: CLIServiceError.self) {
            _ = try parser.parse("not json")
        }
    }
}
