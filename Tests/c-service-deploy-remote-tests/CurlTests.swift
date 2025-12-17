import d_sdk_cli
@testable import c_service_deploy_remote
import Testing

@Suite("curl CLI Command Tests")
struct CurlCLITests {

    @Test("Curl program name")
    func testProgramName() {
        #expect(Curl.programName == "curl")
    }
}

// MARK: - Request Command Tests

@Suite("curl Request Tests")
struct CurlRequestTests {

    @Test("Request command path is empty (root command)")
    func testCommandPath() {
        #expect(Curl.Request.commandPath == [])
    }

    @Test("Simple GET request")
    func testSimpleGet() {
        let cmd = Curl.Request(url: "https://example.com")
        #expect(cmd.commandLine == ["curl", "https://example.com"])
    }

    @Test("GET request with method flag")
    func testGetWithMethod() {
        let cmd = Curl.Request(method: "GET", url: "https://example.com/api")
        #expect(cmd.commandLine == ["curl", "-X", "GET", "https://example.com/api"])
    }

    @Test("POST request")
    func testPostRequest() {
        let cmd = Curl.Request(method: "POST", url: "https://example.com/api")
        #expect(cmd.commandLine == ["curl", "-X", "POST", "https://example.com/api"])
    }

    @Test("POST request with data")
    func testPostWithData() {
        let cmd = Curl.Request(method: "POST", data: "{\"key\":\"value\"}", url: "https://example.com/api")
        #expect(cmd.commandLine == ["curl", "-X", "POST", "-d", "{\"key\":\"value\"}", "https://example.com/api"])
    }

    @Test("Request with single header")
    func testSingleHeader() {
        let cmd = Curl.Request(headers: ["Content-Type: application/json"], url: "https://example.com")
        #expect(cmd.commandLine == ["curl", "-H", "Content-Type: application/json", "https://example.com"])
    }

    @Test("Request with multiple headers")
    func testMultipleHeaders() {
        let cmd = Curl.Request(
            headers: ["Content-Type: application/json", "Authorization: Bearer token"],
            url: "https://example.com"
        )
        #expect(cmd.commandLine == [
            "curl",
            "-H", "Content-Type: application/json",
            "-H", "Authorization: Bearer token",
            "https://example.com"
        ])
    }

    @Test("Verbose request")
    func testVerboseRequest() {
        let cmd = Curl.Request(verbose: true, url: "https://example.com")
        #expect(cmd.commandLine == ["curl", "-v", "https://example.com"])
    }

    @Test("Silent request")
    func testSilentRequest() {
        let cmd = Curl.Request(silent: true, url: "https://example.com")
        #expect(cmd.commandLine == ["curl", "-s", "https://example.com"])
    }

    @Test("Request with output file")
    func testOutputFile() {
        let cmd = Curl.Request(output: "/tmp/response.txt", url: "https://example.com")
        #expect(cmd.commandLine == ["curl", "-o", "/tmp/response.txt", "https://example.com"])
    }

    @Test("Request with write-out format")
    func testWriteOutFormat() {
        let cmd = Curl.Request(writeOut: "%{http_code}", url: "https://example.com")
        #expect(cmd.commandLine == ["curl", "-w", "%{http_code}", "https://example.com"])
    }

    @Test("Check HTTP status command")
    func testCheckHttpStatus() {
        let cmd = Curl.Request(
            silent: true,
            output: "/dev/null",
            writeOut: "%{http_code}",
            url: "https://example.com/health"
        )
        #expect(cmd.commandLine == [
            "curl",
            "-s",
            "-o", "/dev/null",
            "-w", "%{http_code}",
            "https://example.com/health"
        ])
    }

    @Test("Full verbose POST with JSON")
    func testFullVerbosePostJson() {
        let cmd = Curl.Request(
            method: "POST",
            headers: ["Content-Type: application/json"],
            data: "{\"test\":true}",
            verbose: true,
            url: "https://api.example.com/endpoint"
        )
        #expect(cmd.commandLine == [
            "curl",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", "{\"test\":true}",
            "-v",
            "https://api.example.com/endpoint"
        ])
    }

    @Test("Command string format")
    func testCommandString() {
        let cmd = Curl.Request(method: "GET", silent: true, url: "https://example.com")
        #expect(cmd.commandString == "curl -X GET -s https://example.com")
    }
}

// MARK: - Convenience Initializer Tests

@Suite("curl Request Convenience Initializers")
struct CurlRequestConvenienceTests {

    @Test("Get convenience initializer - minimal")
    func testGetMinimal() {
        let cmd = Curl.Request.get(url: "https://example.com")
        #expect(cmd.commandLine == ["curl", "-X", "GET", "https://example.com"])
    }

    @Test("Get convenience initializer - silent")
    func testGetSilent() {
        let cmd = Curl.Request.get(url: "https://example.com", silent: true)
        #expect(cmd.commandLine == ["curl", "-X", "GET", "-s", "https://example.com"])
    }

    @Test("Get convenience initializer - verbose")
    func testGetVerbose() {
        let cmd = Curl.Request.get(url: "https://example.com", verbose: true)
        #expect(cmd.commandLine == ["curl", "-X", "GET", "-v", "https://example.com"])
    }

    @Test("Post convenience initializer - minimal")
    func testPostMinimal() {
        let cmd = Curl.Request.post(url: "https://example.com/api")
        #expect(cmd.commandLine == ["curl", "-X", "POST", "https://example.com/api"])
    }

    @Test("Post convenience initializer - with data")
    func testPostWithData() {
        let cmd = Curl.Request.post(url: "https://example.com/api", data: "test=value")
        #expect(cmd.commandLine == ["curl", "-X", "POST", "-d", "test=value", "https://example.com/api"])
    }

    @Test("Post convenience initializer - silent")
    func testPostSilent() {
        let cmd = Curl.Request.post(url: "https://example.com/api", silent: true)
        #expect(cmd.commandLine == ["curl", "-X", "POST", "-s", "https://example.com/api"])
    }

    @Test("PostJSON convenience initializer")
    func testPostJson() {
        let cmd = Curl.Request.postJSON(url: "https://example.com/api", data: "{\"key\":\"value\"}")
        #expect(cmd.commandLine == [
            "curl",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", "{\"key\":\"value\"}",
            "https://example.com/api"
        ])
    }

    @Test("PostJSON convenience initializer - verbose")
    func testPostJsonVerbose() {
        let cmd = Curl.Request.postJSON(url: "https://example.com/api", data: "{}", verbose: true)
        #expect(cmd.commandLine == [
            "curl",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", "{}",
            "-v",
            "https://example.com/api"
        ])
    }

    @Test("CheckStatus convenience initializer")
    func testCheckStatus() {
        let cmd = Curl.Request.checkStatus(url: "https://example.com/health")
        #expect(cmd.commandLine == [
            "curl",
            "-s",
            "-o", "/dev/null",
            "-w", "%{http_code}",
            "https://example.com/health"
        ])
    }
}
