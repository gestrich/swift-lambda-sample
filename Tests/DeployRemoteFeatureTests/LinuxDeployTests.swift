//
//  LinuxDeployTests.swift
//  SwiftDeploy
//
//  Created by Bill Gestrich on 11/16/25.
//

import Foundation
import CLISDK
@testable import DeployRemoteFeature
@testable import DeployLocalService
@testable import DeployLocalLinuxFeature
import Testing

@Suite("Linux Lambda Container Integration Tests")
@MainActor
struct LinuxContainerIntegrationTests {

    let cliClient: CLIClient
    let projectRoot: URL
    let workingDirectory: String

    init() {
        // Calculate project root at init time (assuming tests are in Tests/SwiftDeployTests/)
        // When running from Xcode, we need to find the project root
        // #filePath gives absolute path at compile time
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Remove LinuxDeployTests.swift
            .deletingLastPathComponent()  // Remove SwiftDeployTests
            .deletingLastPathComponent()  // Remove Tests

        self.projectRoot = root
        self.workingDirectory = root.path
        self.cliClient = CLIClient()
    }

    @Test("Full Linux container workflow: build, start services, run in container, test endpoints, cleanup")
    func testLinuxContainerWorkflow() async throws {
        // Ensure cleanup happens even if test fails
        defer {
            // Async cleanup
            Task {
                print("🧹 Cleanup: Stopping Lambda container and services...")

                // Stop Lambda container using workflow
                let stopLambdaComponents = LinuxStopLambdaWorkflow.create(workingDirectory: workingDirectory)
                for try await _ in stopLambdaComponents.workflow.stream() {
                    // Consume progress
                }

                // Stop services using workflow
                let stopServicesComponents = LinuxStopServicesWorkflow.create(workingDirectory: workingDirectory)
                for try await _ in stopServicesComponents.workflow.stream(options: .all) {
                    // Consume progress
                }
            }
        }

        // Step 1: Start local services (PostgreSQL + MinIO) - do this first for debugging
        print("🚀 Step 1: Starting local services...")
        let startServicesComponents = LinuxStartServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in startServicesComponents.workflow.stream(options: .all) {
            // Consume progress
        }

        // Give services time to fully start
        try await Task.sleep(for: .seconds(5))

        // Setup Lambda network
        print("🔧 Step 2: Setting up Docker network...")
        let setupNetworkComponents = LinuxSetupNetworkWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in setupNetworkComponents.workflow.stream() {
            // Consume progress
        }

        // Create MinIO bucket for testing (already done by start services workflow)

        // Step 3: Build Lambda (skip if already built)
        print("🔨 Step 3: Checking Lambda build...")
        let buildComponents = LinuxBuildWorkflow.create(workingDirectory: workingDirectory)
        let isBuilt = buildComponents.workflow.isLambdaBuilt()
        if isBuilt {
            print("  ✅ Lambda already built, skipping build step")
        } else {
            print("  → Lambda not built, building now...")
            for try await _ in buildComponents.workflow.stream(options: LinuxBuildWorkflow.Options(clean: false)) {
                // Consume progress
            }
            // Give filesystem time to sync after build
            try await Task.sleep(for: .seconds(2))
        }

        // Verify build artifacts exist
        try await verifyBuildArtifacts()

        // Step 4: Start Lambda in container (background mode) using workflow
        print("🚀 Step 4: Starting Lambda in Linux container...")
        let startLambdaComponents = LinuxStartLambdaWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in startLambdaComponents.workflow.stream() {
            // Consume progress
        }

        // Give Lambda time to start
        try await Task.sleep(for: .seconds(5))

        // Step 5: Test S3 endpoint
        print("🧪 Step 5: Testing S3 file upload/download...")
        try await testS3Endpoint()

        // Step 6: Test PostgreSQL endpoint
        print("🧪 Step 6: Testing PostgreSQL database initialization...")
        try await testPostgresEndpoint()

        // Step 7: Stop Lambda container using workflow
        print("🛑 Step 7: Stopping Lambda container...")
        let stopLambdaComponents = LinuxStopLambdaWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in stopLambdaComponents.workflow.stream() {
            // Consume progress
        }

        // Step 8: Stop services using workflow
        print("🧹 Step 8: Stopping local services...")
        let stopServicesComponents = LinuxStopServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in stopServicesComponents.workflow.stream(options: .all) {
            // Consume progress
        }

        print("✅ All Linux container integration tests passed!")
    }

    // MARK: - Helper Methods

    private func verifyBuildArtifacts() async throws {
        print("🔍 Verifying build artifacts...")

        // Check lambda directory exists
        let lambdaDir = "\(projectRoot.path)/lambda"
        let lambdaDirExists = FileManager.default.fileExists(atPath: lambdaDir)
        #expect(lambdaDirExists, "lambda/ directory should exist after build")

        // Check bootstrap executable exists
        let bootstrapPath = "\(lambdaDir)/bootstrap"
        let bootstrapExists = FileManager.default.fileExists(atPath: bootstrapPath)
        #expect(bootstrapExists, "lambda/bootstrap should exist after build")

        // Check lambda.zip exists
        let zipPath = "\(projectRoot.path)/lambda.zip"
        let zipExists = FileManager.default.fileExists(atPath: zipPath)
        #expect(zipExists, "lambda.zip should exist after build")

        print("  ✅ All build artifacts present")
    }


    private func testS3Endpoint() async throws {
        let config = LinuxContainerConfig.default(workingDirectory: workingDirectory)
        let endpoint = "http://localhost:\(config.hostPort)/invoke"

        let payload = """
        {
          "resource": "/api/file",
          "path": "/api/file",
          "httpMethod": "POST",
          "headers": {},
          "multiValueHeaders": {},
          "requestContext": {
            "resourceId": "test",
            "apiId": "test",
            "resourcePath": "/api/file",
            "httpMethod": "POST",
            "requestId": "test",
            "accountId": "123456789012",
            "stage": "local",
            "identity": {"sourceIp": "127.0.0.1"},
            "path": "/api/file"
          },
          "body": null,
          "isBase64Encoded": false
        }
        """

        let response = try await curlPost(endpoint: endpoint, payload: payload)

        #expect(response.contains("File uploaded and downloaded"),
                "S3 endpoint should return success message. Got: \(response)")

        print("  ✅ S3 test passed")
    }

    private func testPostgresEndpoint() async throws {
        let config = LinuxContainerConfig.default(workingDirectory: workingDirectory)
        let endpoint = "http://localhost:\(config.hostPort)/invoke"

        let payload = """
        {
          "resource": "/api/database",
          "path": "/api/database",
          "httpMethod": "POST",
          "headers": {},
          "multiValueHeaders": {},
          "requestContext": {
            "resourceId": "test",
            "apiId": "test",
            "resourcePath": "/api/database",
            "httpMethod": "POST",
            "requestId": "test",
            "accountId": "123456789012",
            "stage": "local",
            "identity": {"sourceIp": "127.0.0.1"},
            "path": "/api/database"
          },
          "body": null,
          "isBase64Encoded": false
        }
        """

        let response = try await curlPost(endpoint: endpoint, payload: payload)

        #expect(response.contains("Database Initialized"),
                "Database endpoint should return success message. Got: \(response)")

        print("  ✅ Database test passed")
    }

    private func curlPost(endpoint: String, payload: String) async throws -> String {
        // Write payload to temp file to avoid shell escaping issues
        let tempFile = "/tmp/test_payload_\(UUID().uuidString).json"
        try payload.write(toFile: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(atPath: tempFile)
        }

        let result = try await cliClient.execute(
            command: "curl",
            arguments: [
                "-s",
                "-X", "POST",
                endpoint,
                "-H", "Content-Type: application/json",
                "-d", "@\(tempFile)"
            ],
            printCommand: false
        )

        return result.stdout.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}
