import CLIKit
import Testing

@Suite("Id Command Tests")
struct IdCommandTests {

    @Test("Id program name")
    func testProgramName() {
        #expect(Id.programName == "id")
    }

    @Test("Id command line with userId flag")
    func testIdUserId() {
        let cmd = Id(userId: true)
        #expect(cmd.commandLine == ["id", "-u"])
    }

    @Test("Id command line with groupId flag")
    func testIdGroupId() {
        let cmd = Id(groupId: true)
        #expect(cmd.commandLine == ["id", "-g"])
    }

    @Test("Id command line with no flags")
    func testIdNoFlags() {
        let cmd = Id()
        #expect(cmd.commandLine == ["id"])
    }

    @Test("Id command string with userId")
    func testIdCommandString() {
        let cmd = Id(userId: true)
        #expect(cmd.commandString == "id -u")
    }

    @Test("IdParser parses valid integer")
    func testIdParserValid() throws {
        let parser = IdParser()
        let result = try parser.parse("501\n")
        #expect(result == 501)
    }

    @Test("IdParser handles whitespace")
    func testIdParserWhitespace() throws {
        let parser = IdParser()
        let result = try parser.parse("  20  \n")
        #expect(result == 20)
    }

    @Test("IdParser throws on invalid input")
    func testIdParserInvalid() {
        let parser = IdParser()
        #expect(throws: CLIServiceError.self) {
            try parser.parse("not-a-number")
        }
    }
}

@Suite("Kill Command Tests")
struct KillCommandTests {

    @Test("Kill program name")
    func testProgramName() {
        #expect(Kill.programName == "kill")
    }

    @Test("Kill command line with PID only")
    func testKillPidOnly() {
        let cmd = Kill(pid: "12345")
        #expect(cmd.commandLine == ["kill", "12345"])
    }

    @Test("Kill command line with signal")
    func testKillWithSignal() {
        let cmd = Kill(signal: "9", pid: "12345")
        #expect(cmd.commandLine == ["kill", "-9", "12345"])
    }

    @Test("Kill command line with TERM signal")
    func testKillWithTermSignal() {
        let cmd = Kill(signal: "TERM", pid: "12345")
        #expect(cmd.commandLine == ["kill", "-TERM", "12345"])
    }

    @Test("Kill command string")
    func testKillCommandString() {
        let cmd = Kill(signal: "9", pid: "12345")
        #expect(cmd.commandString == "kill -9 12345")
    }
}

@Suite("Lsof Command Tests")
struct LsofCommandTests {

    @Test("Lsof program name")
    func testProgramName() {
        #expect(Lsof.programName == "lsof")
    }

    @Test("Lsof command line")
    func testLsof() {
        let cmd = Lsof(port: ":8080")
        #expect(cmd.commandLine == ["lsof", "-i", ":8080"])
    }

    @Test("Lsof with different port")
    func testLsofDifferentPort() {
        let cmd = Lsof(port: ":3000")
        #expect(cmd.commandLine == ["lsof", "-i", ":3000"])
    }

    @Test("Lsof with pidOnly flag")
    func testLsofPidOnly() {
        let cmd = Lsof(port: ":8080", pidOnly: true)
        #expect(cmd.commandLine == ["lsof", "-i", ":8080", "-t"])
    }

    @Test("Lsof command string")
    func testLsofCommandString() {
        let cmd = Lsof(port: ":8080", pidOnly: true)
        #expect(cmd.commandString == "lsof -i :8080 -t")
    }
}
