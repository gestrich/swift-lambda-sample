import d_sdk_cli
import c_service_lambda_build
@testable import c_service_deploy_remote
import Testing

@Suite("Swift CLI Command Tests")
struct SwiftCLITests {

    @Test("Swift program name")
    func testProgramName() {
        #expect(SwiftCLI.programName == "swift")
    }
}

// MARK: - Package Commands

@Suite("Swift Package Clean Tests")
struct SwiftPackageCleanTests {

    @Test("Package.Clean command path")
    func testCommandPath() {
        #expect(SwiftCLI.Package.Clean.commandPath == ["package", "clean"])
    }

    @Test("Package.Clean command line")
    func testCommandLine() {
        let cmd = SwiftCLI.Package.Clean()
        #expect(cmd.commandLine == ["swift", "package", "clean"])
    }

    @Test("Package.Clean command string")
    func testCommandString() {
        let cmd = SwiftCLI.Package.Clean()
        #expect(cmd.commandString == "swift package clean")
    }
}

// MARK: - Build Commands

@Suite("Swift Build Tests")
struct SwiftBuildTests {

    @Test("Build command path")
    func testCommandPath() {
        #expect(SwiftCLI.Build.commandPath == ["build"])
    }

    @Test("Build minimal command line")
    func testMinimalCommandLine() {
        let cmd = SwiftCLI.Build()
        #expect(cmd.commandLine == ["swift", "build"])
    }

    @Test("Build with product option")
    func testWithProduct() {
        let cmd = SwiftCLI.Build(product: "SwiftLambda")
        #expect(cmd.commandLine == ["swift", "build", "--product", "SwiftLambda"])
    }

    @Test("Build with showBinPath flag")
    func testWithShowBinPath() {
        let cmd = SwiftCLI.Build(showBinPath: true)
        #expect(cmd.commandLine == ["swift", "build", "--show-bin-path"])
    }

    @Test("Build with product and showBinPath")
    func testWithProductAndShowBinPath() {
        let cmd = SwiftCLI.Build(product: "SwiftLambda", showBinPath: true)
        #expect(cmd.commandLine == ["swift", "build", "--product", "SwiftLambda", "--show-bin-path"])
    }

    @Test("Build command string with product")
    func testCommandStringWithProduct() {
        let cmd = SwiftCLI.Build(product: "MyApp")
        #expect(cmd.commandString == "swift build --product MyApp")
    }

    @Test("Build command string with all options")
    func testCommandStringWithAllOptions() {
        let cmd = SwiftCLI.Build(product: "SwiftLambda", showBinPath: true)
        #expect(cmd.commandString == "swift build --product SwiftLambda --show-bin-path")
    }
}
