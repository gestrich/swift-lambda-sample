//
//  XcodeDeployTests.swift
//  SwiftDeploy
//
//  Created by Bill Gestrich on 11/16/25.
//

import Foundation
import Testing

@Suite("Local Xcode Lambda Integration Tests")
struct XcodeLocalIntegrationTests {

    let port = 8080

    // Get the project root directory (assuming tests are in Tests/SwiftDeployTests/)
    var toolsScript: String {
        // When running from Xcode, we need to find the project root
        // #filePath gives absolute path at compile time
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Remove XcodeDeployTests.swift
            .deletingLastPathComponent()  // Remove SwiftDeployTests
            .deletingLastPathComponent()  // Remove Tests
        return "\(projectRoot.path)/tools.sh"
    }

    @Test("Full local development workflow: start services, run Lambda, test endpoints, stop services")
    func testLocalDevelopmentWorkflow() async throws {
        // Ensure cleanup happens even if test fails
        defer {
            // Synchronous cleanup - run shell commands directly
            print("🧹 Cleanup: Stopping Lambda and services...")
            let process1 = Process()
            process1.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process1.arguments = ["-c", "\(toolsScript) stopLocalLambda \(port)"]
            process1.currentDirectoryURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            try? process1.run()
            process1.waitUntilExit()

            let process2 = Process()
            process2.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process2.arguments = ["-c", "\(toolsScript) stopServices"]
            process2.currentDirectoryURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            try? process2.run()
            process2.waitUntilExit()
        }

        // Step 1: Copy configuration file
        print("📋 Step 1: Copying configuration file...")
        _ = try await runShellCommand("\(toolsScript) copyConfig")

        // Step 2: Start local services (PostgreSQL + MinIO)
        print("🚀 Step 2: Starting local services...")
        _ = try await runShellCommand("\(toolsScript) startServices")

        // Give services time to fully start
        try await Task.sleep(for: .seconds(3))

        // Verify services are running
        try await verifyServicesRunning()

        // Step 3: Start Lambda locally in background
        print("🔧 Step 3: Starting Lambda locally on port \(port)...")
        _ = try await runShellCommand("\(toolsScript) runLocalLambda \(port) bg")

        // Step 3b: Wait for Lambda to be ready
        print("⏳ Step 3b: Waiting for Lambda to be ready...")
        _ = try await runShellCommand("\(toolsScript) waitForLambda \(port)")

        // Step 4: Test S3 endpoint
        print("🧪 Step 4: Testing S3 file upload/download...")
        try await testS3Endpoint()

        // Step 5: Test PostgreSQL endpoint
        print("🧪 Step 5: Testing PostgreSQL database initialization...")
        try await testPostgresEndpoint()

        // Step 6: Stop Lambda
        print("🛑 Step 6: Stopping Lambda...")
        _ = try await runShellCommand("\(toolsScript) stopLocalLambda \(port)")

        // Step 7: Stop services
        print("🧹 Step 7: Stopping local services...")
        _ = try await runShellCommand("\(toolsScript) stopServices")

        print("✅ All integration tests passed!")
    }

    // MARK: - Helper Methods

    private func verifyServicesRunning() async throws {
        print("🔍 Verifying services are running...")

        // Check PostgreSQL
        let postgresRunning = try await runShellCommand("docker ps --filter name=postgres_lambda --format '{{.Names}}'")
        #expect(postgresRunning.contains("postgres_lambda"), "PostgreSQL container should be running")

        // Check MinIO
        let minioRunning = try await runShellCommand("docker ps --filter name=minio_lambda --format '{{.Names}}'")
        #expect(minioRunning.contains("minio_lambda"), "MinIO container should be running")

        print("  ✅ All services are running")
    }

    private func testS3Endpoint() async throws {
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

        let command = """
        curl -s -X POST '\(endpoint)' \
          -H 'Content-Type: application/json' \
          -d @\(tempFile)
        """

        return try await runShellCommand(command)
    }

    private func runShellCommand(_ command: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        // Set working directory to project root
        // #filePath gives absolute path at compile time
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Remove XcodeDeployTests.swift
            .deletingLastPathComponent()  // Remove SwiftDeployTests
            .deletingLastPathComponent()  // Remove Tests
        process.currentDirectoryURL = projectRoot

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            print("❌ Command failed: \(command)")
            print("   Output: \(output)")
            print("   Error: \(error)")
            throw TestError.commandFailed(
                command: command,
                exitCode: process.terminationStatus,
                output: output,
                error: error
            )
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TestError: Error, CustomStringConvertible {
    case commandFailed(command: String, exitCode: Int32, output: String, error: String)

    var description: String {
        switch self {
        case .commandFailed(let command, let exitCode, let output, let error):
            return """
            Command failed with exit code \(exitCode):
            Command: \(command)
            Output: \(output)
            Error: \(error)
            """
        }
    }
}
