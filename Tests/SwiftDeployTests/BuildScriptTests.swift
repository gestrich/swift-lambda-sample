import CLIKit
@testable import SwiftDeploy
import Testing

@Suite("BuildScript CLI Command Tests")
struct BuildScriptCLITests {

    @Test("BuildScript program name")
    func testProgramName() {
        #expect(BuildScript.programName == "./build.sh")
    }
}

// MARK: - Build Command Tests

@Suite("BuildScript Build Command Tests")
struct BuildScriptBuildTests {

    @Test("Build command path is empty (root command)")
    func testCommandPath() {
        #expect(BuildScript.Build.commandPath == [])
    }

    @Test("Build with target only")
    func testBuildWithTargetOnly() {
        let cmd = BuildScript.Build(target: "SwiftLambda")
        #expect(cmd.commandLine == ["./build.sh", "SwiftLambda"])
    }

    @Test("Build with target and platform")
    func testBuildWithPlatform() {
        let cmd = BuildScript.Build(target: "SwiftLambda", platform: "linux/amd64")
        #expect(cmd.commandLine == ["./build.sh", "SwiftLambda", "linux/amd64"])
    }

    @Test("Build with target, platform, and GitHub token")
    func testBuildWithAllArgs() {
        let cmd = BuildScript.Build(
            target: "SwiftLambda",
            platform: "linux/amd64",
            githubToken: "ghp_token123"
        )
        #expect(cmd.commandLine == ["./build.sh", "SwiftLambda", "linux/amd64", "ghp_token123"])
    }

    @Test("Build with ARM64 platform")
    func testBuildArm64() {
        let cmd = BuildScript.Build(target: "SwiftLambda", platform: "linux/arm64")
        #expect(cmd.commandLine == ["./build.sh", "SwiftLambda", "linux/arm64"])
    }

    @Test("Build with different target name")
    func testBuildDifferentTarget() {
        let cmd = BuildScript.Build(target: "MyLambdaFunction")
        #expect(cmd.commandLine == ["./build.sh", "MyLambdaFunction"])
    }

    @Test("Command string format")
    func testCommandString() {
        let cmd = BuildScript.Build(target: "SwiftLambda", platform: "linux/amd64")
        #expect(cmd.commandString == "./build.sh SwiftLambda linux/amd64")
    }
}

// MARK: - Convenience Initializer Tests

@Suite("BuildScript Build Convenience Initializers")
struct BuildScriptBuildConvenienceTests {

    @Test("Lambda convenience initializer")
    func testLambdaConvenience() {
        let cmd = BuildScript.Build.lambda(target: "SwiftLambda")
        #expect(cmd.commandLine == ["./build.sh", "SwiftLambda"])
    }

    @Test("Lambda convenience with different target")
    func testLambdaConvenienceDifferentTarget() {
        let cmd = BuildScript.Build.lambda(target: "MyFunction")
        #expect(cmd.commandLine == ["./build.sh", "MyFunction"])
    }

    @Test("ForPlatform convenience initializer")
    func testForPlatformConvenience() {
        let cmd = BuildScript.Build.forPlatform(target: "SwiftLambda", platform: "linux/arm64")
        #expect(cmd.commandLine == ["./build.sh", "SwiftLambda", "linux/arm64"])
    }

    @Test("ForPlatform convenience with amd64")
    func testForPlatformAmd64() {
        let cmd = BuildScript.Build.forPlatform(target: "SwiftLambda", platform: "linux/amd64")
        #expect(cmd.commandLine == ["./build.sh", "SwiftLambda", "linux/amd64"])
    }

    @Test("WithToken convenience initializer - no platform")
    func testWithTokenNoPlatform() {
        let cmd = BuildScript.Build.withToken(target: "SwiftLambda", githubToken: "ghp_abc123")
        #expect(cmd.commandLine == ["./build.sh", "SwiftLambda", "ghp_abc123"])
    }

    @Test("WithToken convenience initializer - with platform")
    func testWithTokenWithPlatform() {
        let cmd = BuildScript.Build.withToken(
            target: "SwiftLambda",
            platform: "linux/amd64",
            githubToken: "ghp_abc123"
        )
        #expect(cmd.commandLine == ["./build.sh", "SwiftLambda", "linux/amd64", "ghp_abc123"])
    }

    @Test("WithToken convenience with real-looking token")
    func testWithTokenRealFormat() {
        let cmd = BuildScript.Build.withToken(
            target: "SwiftLambda",
            platform: "linux/amd64",
            githubToken: "ghp_1234567890abcdefghijklmnopqrstuvwxyz"
        )
        #expect(cmd.commandLine == [
            "./build.sh",
            "SwiftLambda",
            "linux/amd64",
            "ghp_1234567890abcdefghijklmnopqrstuvwxyz"
        ])
    }
}
