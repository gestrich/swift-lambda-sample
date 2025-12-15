//
//  LinuxDeployTests.swift
//  SwiftDeploy
//
//  Created by Bill Gestrich on 11/16/25.
//

import Foundation
import Testing
@testable import service_deploy

@Suite("Linux Lambda Container Integration Tests")
@MainActor
struct LinuxContainerIntegrationTests {

    let linuxService: LinuxLocalService
    let cliService: CLIClient
    let projectRoot: URL

    init() {
        // Calculate project root at init time (assuming tests are in Tests/SwiftDeployTests/)
        // When running from Xcode, we need to find the project root
        // #filePath gives absolute path at compile time
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Remove LinuxDeployTests.swift
            .deletingLastPathComponent()  // Remove SwiftDeployTests
            .deletingLastPathComponent()  // Remove Tests

        self.projectRoot = root
        self.cliService = CLIClient()
        self.linuxService = LinuxLocalService(workingDirectory: root.path)
    }

    @Test("Full Linux container workflow: build, start services, run in container, test endpoints, cleanup")
    func testLinuxContainerWorkflow() async throws {
        // Ensure cleanup happens even if test fails
        defer {
            // Async cleanup
            Task {
                print("🧹 Cleanup: Stopping Lambda container and services...")

                // Stop Lambda container using protocol method
                try? await linuxService.stopLambda()

                // Stop services
                try? await linuxService.stopAllServices()
            }
        }

        // Step 1: Start local services (PostgreSQL + MinIO) - do this first for debugging
        print("🚀 Step 1: Starting local services...")
        try await linuxService.startAllServices()

        // Give services time to fully start
        try await Task.sleep(for: .seconds(5))

        // Setup Lambda network
        print("🔧 Step 2: Setting up Docker network...")
        try await linuxService.setupDockerNetwork()

        // Create MinIO bucket for testing
        try await linuxService.createBucket()

        // Step 3: Build Lambda (skip if already built)
        print("🔨 Step 3: Checking Lambda build...")
        let isBuilt = linuxService.isLambdaBuilt()
        if isBuilt {
            print("  ✅ Lambda already built, skipping build step")
        } else {
            print("  → Lambda not built, building now...")
            try await linuxService.build()
            // Give filesystem time to sync after build
            try await Task.sleep(for: .seconds(2))
        }

        // Verify build artifacts exist
        try await verifyBuildArtifacts()

        // Step 4: Start Lambda in container (background mode) using protocol method
        print("🚀 Step 4: Starting Lambda in Linux container...")
        try await linuxService.startDetached(
            lambdaPath: "\(projectRoot.path)/lambda"
        )

        // Give Lambda time to start
        try await Task.sleep(for: .seconds(5))

        // Verify Lambda is running and ready using protocol method
        try await linuxService.waitForReady()

        // Step 5: Test S3 endpoint
        print("🧪 Step 5: Testing S3 file upload/download...")
        try await testS3Endpoint()

        // Step 6: Test PostgreSQL endpoint
        print("🧪 Step 6: Testing PostgreSQL database initialization...")
        try await testPostgresEndpoint()

        // Step 7: Stop Lambda container using protocol method
        print("🛑 Step 7: Stopping Lambda container...")
        try await linuxService.stopLambda()

        // Step 8: Stop services
        print("🧹 Step 8: Stopping local services...")
        try await linuxService.stopAllServices()

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
        let port = linuxService.port
        let endpoint = "http://localhost:\(port)/invoke"

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
        let port = linuxService.port
        let endpoint = "http://localhost:\(port)/invoke"

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

        let result = try await cliService.execute(
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

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
