import AWSSDK
import CLISDK
@testable import c_service_deploy_remote
import Testing

@Suite("CDK CLI Command Tests")
struct CDKCLITests {

    @Test("Cdk program name")
    func testProgramName() {
        #expect(Cdk.programName == "cdk")
    }
}

// MARK: - Deploy Command Tests

@Suite("CDK Deploy Tests")
struct CDKDeployTests {

    @Test("Deploy command path")
    func testCommandPath() {
        #expect(Cdk.Deploy.commandPath == ["deploy"])
    }

    @Test("Deploy minimal command line")
    func testMinimalCommandLine() {
        let cmd = Cdk.Deploy()
        #expect(cmd.commandLine == ["cdk", "deploy"])
    }

    @Test("Deploy with profile")
    func testWithProfile() {
        let cmd = Cdk.Deploy(profile: "prod")
        #expect(cmd.commandLine == ["cdk", "deploy", "--profile", "prod"])
    }

    @Test("Deploy with require-approval")
    func testWithRequireApproval() {
        let cmd = Cdk.Deploy(profile: "prod", requireApproval: "never")
        #expect(cmd.commandLine == [
            "cdk", "deploy",
            "--profile", "prod",
            "--require-approval", "never"
        ])
    }

    @Test("Deploy with single context")
    func testWithSingleContext() {
        let cmd = Cdk.Deploy(profile: "prod", context: ["skipPostgres=true"])
        #expect(cmd.commandLine == [
            "cdk", "deploy",
            "--profile", "prod",
            "--context", "skipPostgres=true"
        ])
    }

    @Test("Deploy with multiple context values")
    func testWithMultipleContext() {
        let cmd = Cdk.Deploy(
            profile: "prod",
            requireApproval: "never",
            context: ["skipPostgres=true", "skipNATGateway=true"]
        )
        #expect(cmd.commandLine == [
            "cdk", "deploy",
            "--profile", "prod",
            "--require-approval", "never",
            "--context", "skipPostgres=true",
            "--context", "skipNATGateway=true"
        ])
    }

    @Test("Deploy with outputs file")
    func testWithOutputsFile() {
        let cmd = Cdk.Deploy(profile: "prod", outputsFile: "outputs.json")
        #expect(cmd.commandLine == [
            "cdk", "deploy",
            "--profile", "prod",
            "--outputs-file", "outputs.json"
        ])
    }

    @Test("Deploy full command")
    func testFullCommand() {
        let cmd = Cdk.Deploy(
            profile: "production",
            requireApproval: "any-change",
            context: ["skipPostgres=true", "skipNATGateway=true"],
            outputsFile: "cdk-outputs.json"
        )
        #expect(cmd.commandLine == [
            "cdk", "deploy",
            "--profile", "production",
            "--require-approval", "any-change",
            "--context", "skipPostgres=true",
            "--context", "skipNATGateway=true",
            "--outputs-file", "cdk-outputs.json"
        ])
    }

    @Test("Deploy command string")
    func testCommandString() {
        let cmd = Cdk.Deploy(profile: "prod", requireApproval: "never")
        #expect(cmd.commandString == "cdk deploy --profile prod --require-approval never")
    }
}

// MARK: - Destroy Command Tests

@Suite("CDK Destroy Tests")
struct CDKDestroyTests {

    @Test("Destroy command path")
    func testCommandPath() {
        #expect(Cdk.Destroy.commandPath == ["destroy"])
    }

    @Test("Destroy minimal command line")
    func testMinimalCommandLine() {
        let cmd = Cdk.Destroy()
        #expect(cmd.commandLine == ["cdk", "destroy"])
    }

    @Test("Destroy with profile")
    func testWithProfile() {
        let cmd = Cdk.Destroy(profile: "prod")
        #expect(cmd.commandLine == ["cdk", "destroy", "--profile", "prod"])
    }

    @Test("Destroy with force flag")
    func testWithForce() {
        let cmd = Cdk.Destroy(profile: "prod", force: true)
        #expect(cmd.commandLine == [
            "cdk", "destroy",
            "--profile", "prod",
            "--force"
        ])
    }

    @Test("Destroy command string")
    func testCommandString() {
        let cmd = Cdk.Destroy(profile: "prod", force: true)
        #expect(cmd.commandString == "cdk destroy --profile prod --force")
    }
}

// MARK: - Diff Command Tests

@Suite("CDK Diff Tests")
struct CDKDiffTests {

    @Test("Diff command path")
    func testCommandPath() {
        #expect(Cdk.Diff.commandPath == ["diff"])
    }

    @Test("Diff minimal command line")
    func testMinimalCommandLine() {
        let cmd = Cdk.Diff()
        #expect(cmd.commandLine == ["cdk", "diff"])
    }

    @Test("Diff with profile")
    func testWithProfile() {
        let cmd = Cdk.Diff(profile: "prod")
        #expect(cmd.commandLine == ["cdk", "diff", "--profile", "prod"])
    }

    @Test("Diff command string")
    func testCommandString() {
        let cmd = Cdk.Diff(profile: "prod")
        #expect(cmd.commandString == "cdk diff --profile prod")
    }
}

// MARK: - Synth Command Tests

@Suite("CDK Synth Tests")
struct CDKSynthTests {

    @Test("Synth command path")
    func testCommandPath() {
        #expect(Cdk.Synth.commandPath == ["synth"])
    }

    @Test("Synth minimal command line")
    func testMinimalCommandLine() {
        let cmd = Cdk.Synth()
        #expect(cmd.commandLine == ["cdk", "synth"])
    }

    @Test("Synth with profile")
    func testWithProfile() {
        let cmd = Cdk.Synth(profile: "prod")
        #expect(cmd.commandLine == ["cdk", "synth", "--profile", "prod"])
    }

    @Test("Synth command string")
    func testCommandString() {
        let cmd = Cdk.Synth(profile: "prod")
        #expect(cmd.commandString == "cdk synth --profile prod")
    }
}

// MARK: - List Command Tests

@Suite("CDK List Tests")
struct CDKListTests {

    @Test("List command path")
    func testCommandPath() {
        #expect(Cdk.List.commandPath == ["list"])
    }

    @Test("List minimal command line")
    func testMinimalCommandLine() {
        let cmd = Cdk.List()
        #expect(cmd.commandLine == ["cdk", "list"])
    }

    @Test("List with profile")
    func testWithProfile() {
        let cmd = Cdk.List(profile: "prod")
        #expect(cmd.commandLine == ["cdk", "list", "--profile", "prod"])
    }

    @Test("List command string")
    func testCommandString() {
        let cmd = Cdk.List(profile: "prod")
        #expect(cmd.commandString == "cdk list --profile prod")
    }
}

// MARK: - Bootstrap Command Tests

@Suite("CDK Bootstrap Tests")
struct CDKBootstrapTests {

    @Test("Bootstrap command path")
    func testCommandPath() {
        #expect(Cdk.Bootstrap.commandPath == ["bootstrap"])
    }

    @Test("Bootstrap minimal command line")
    func testMinimalCommandLine() {
        let cmd = Cdk.Bootstrap()
        #expect(cmd.commandLine == ["cdk", "bootstrap"])
    }

    @Test("Bootstrap with profile")
    func testWithProfile() {
        let cmd = Cdk.Bootstrap(profile: "prod")
        #expect(cmd.commandLine == ["cdk", "bootstrap", "--profile", "prod"])
    }

    @Test("Bootstrap command string")
    func testCommandString() {
        let cmd = Cdk.Bootstrap(profile: "prod")
        #expect(cmd.commandString == "cdk bootstrap --profile prod")
    }
}
