import CLIKit
@testable import SwiftDeploy
import Testing

@Suite("npm CLI Command Tests")
struct NpmCLITests {

    @Test("Npm program name")
    func testProgramName() {
        #expect(Npm.programName == "npm")
    }
}

// MARK: - Run Command Tests

@Suite("npm Run Tests")
struct NpmRunTests {

    @Test("Run command name")
    func testCommandName() {
        #expect(Npm.Run.commandName == "run")
    }

    @Test("Run build script")
    func testRunBuild() {
        let cmd = Npm.Run(script: "build")
        #expect(cmd.commandLine == ["npm", "run", "build"])
    }

    @Test("Run test script")
    func testRunTest() {
        let cmd = Npm.Run(script: "test")
        #expect(cmd.commandLine == ["npm", "run", "test"])
    }

    @Test("Run custom script")
    func testRunCustomScript() {
        let cmd = Npm.Run(script: "lint:fix")
        #expect(cmd.commandLine == ["npm", "run", "lint:fix"])
    }

    @Test("Run command string")
    func testCommandString() {
        let cmd = Npm.Run(script: "build")
        #expect(cmd.commandString == "npm run build")
    }
}

// MARK: - Install Command Tests

@Suite("npm Install Tests")
struct NpmInstallTests {

    @Test("Install command name")
    func testCommandName() {
        #expect(Npm.Install.commandName == "install")
    }

    @Test("Install without package (all dependencies)")
    func testInstallAll() {
        let cmd = Npm.Install()
        #expect(cmd.commandLine == ["npm", "install"])
    }

    @Test("Install specific package")
    func testInstallPackage() {
        let cmd = Npm.Install(package: "typescript")
        #expect(cmd.commandLine == ["npm", "install", "typescript"])
    }

    @Test("Install scoped package")
    func testInstallScopedPackage() {
        let cmd = Npm.Install(package: "@aws-cdk/core")
        #expect(cmd.commandLine == ["npm", "install", "@aws-cdk/core"])
    }

    @Test("Install command string")
    func testCommandString() {
        let cmd = Npm.Install()
        #expect(cmd.commandString == "npm install")
    }

    @Test("Install with package command string")
    func testInstallPackageCommandString() {
        let cmd = Npm.Install(package: "typescript")
        #expect(cmd.commandString == "npm install typescript")
    }
}
