//
//  LinuxDeployTests.swift
//  SwiftDeploy
//
//  Created by Bill Gestrich on 11/16/25.
//

import Foundation
import Testing

@Suite("Linux Lambda Container Integration Tests")
struct LinuxContainerIntegrationTests {

    let port = 8080

    // Get the project root directory (assuming tests are in Tests/SwiftDeployTests/)
    var projectRoot: URL {
        // When running from Xcode, we need to find the project root
        // #filePath gives absolute path at compile time
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Remove LinuxDeployTests.swift
            .deletingLastPathComponent()  // Remove SwiftDeployTests
            .deletingLastPathComponent()  // Remove Tests
    }

    var toolsScript: String {
        "\(projectRoot.path)/tools.sh"
    }

    @Test("Full Linux container workflow: build, start services, run in container, test endpoints, cleanup")
    func testLinuxContainerWorkflow() async throws {
        // Ensure cleanup happens even if test fails
        defer {
            // Synchronous cleanup - run shell commands directly
            print("🧹 Cleanup: Stopping Lambda container and services...")

            // Stop any running Lambda containers
            let process1 = Process()
            process1.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process1.arguments = ["-c", "docker ps -q --filter ancestor=swift:5.9.2-amazonlinux2 | xargs -r docker stop"]
            process1.currentDirectoryURL = projectRoot
            try? process1.run()
            process1.waitUntilExit()

            // Stop services
            let process2 = Process()
            process2.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process2.arguments = ["-c", "docker stop postgres_lambda minio_lambda 2>/dev/null || true"]
            process2.currentDirectoryURL = projectRoot
            try? process2.run()
            process2.waitUntilExit()
        }

        // Step 1: Start local services (PostgreSQL + MinIO) - do this first for debugging
        print("🚀 Step 1: Starting local services...")
        // Start PostgreSQL
        _ = try await runShellCommand("docker run -d --name postgres_lambda --rm -p 5432:5432 -e POSTGRES_PASSWORD=docker -e POSTGRES_USER=docker -e POSTGRES_DB=docker postgres:13", allowNonZeroExit: true)
        // Start MinIO
        _ = try await runShellCommand("docker run -d --name minio_lambda --rm -p 9000:9000 -p 9001:9001 -e MINIO_ROOT_USER=admin -e MINIO_ROOT_PASSWORD=password minio/minio server /data --console-address ':9001'", allowNonZeroExit: true)

        // Give services time to fully start
        try await Task.sleep(for: .seconds(5))

        // Verify services are running
        try await verifyServicesRunning()

        // Step 2: Clean previous build artifacts
        print("🧹 Step 2: Cleaning previous build artifacts...")
        _ = try await runShellCommand("rm -rf .aws-sam/build-SwiftLambda lambda lambda.zip", allowNonZeroExit: true)

        // Give filesystem time to sync
        try await Task.sleep(for: .seconds(1))

        // Step 3: Build Lambda for Linux
        print("🔨 Step 3: Building Lambda for Linux...")
        // Use simpler command execution that doesn't capture output to avoid pipe buffer issues
        _ = try await runShellCommandWithoutCapture("./build.sh SwiftLambda")
        print("  ✅ Build completed")

        // Give filesystem time to sync after build
        try await Task.sleep(for: .seconds(2))

        // Verify build artifacts exist
        try await verifyBuildArtifacts()

        // Step 4: Setup Lambda network
        print("🔧 Step 4: Setting up Docker network...")
        _ = try await runShellCommand("docker network create lambda-local 2>/dev/null || true", allowNonZeroExit: true)
        _ = try await runShellCommand("docker network connect lambda-local postgres_lambda 2>/dev/null || true", allowNonZeroExit: true)
        _ = try await runShellCommand("docker network connect lambda-local minio_lambda 2>/dev/null || true", allowNonZeroExit: true)

        // Step 5: Start Lambda in container (background mode)
        print("🚀 Step 5: Starting Lambda in Linux container...")
        try await startLambdaContainer()

        // Give Lambda time to start
        try await Task.sleep(for: .seconds(5))

        // Verify Lambda is running
        try await verifyLambdaRunning()

        // Step 6: Test S3 endpoint
        print("🧪 Step 6: Testing S3 file upload/download...")
        try await testS3Endpoint()

        // Step 7: Test PostgreSQL endpoint
        print("🧪 Step 7: Testing PostgreSQL database initialization...")
        try await testPostgresEndpoint()

        // Step 8: Stop Lambda container
        print("🛑 Step 8: Stopping Lambda container...")
        try await stopLambdaContainer()

        // Step 9: Stop services
        print("🧹 Step 9: Stopping local services...")
        _ = try await runShellCommand("docker stop postgres_lambda minio_lambda", allowNonZeroExit: true)

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

    private func startLambdaContainer() async throws {
        print("🐳 Starting Lambda container in background...")

        // Start the container in detached mode
        let startCommand = """
        docker run -d --rm \
          --name lambda-test-container \
          --platform linux/amd64 \
          --network lambda-local \
          -p \(port):7000 \
          -v "\(projectRoot.path)/lambda:/var/task" \
          -e POSTGRES_HOST=postgres_lambda \
          -e POSTGRES_PORT=5432 \
          -e POSTGRES_USER_NAME=docker \
          -e POSTGRES_DBNAME=docker \
          -e POSTGRES_PASSWORD=docker \
          -e S3_BUCKET_NAME=org.gestrich.sandbox \
          -e AWS_ENDPOINT_URL=http://minio_lambda:9000 \
          -e AWS_ACCESS_KEY_ID=admin \
          -e AWS_SECRET_ACCESS_KEY=password \
          -e MOCK_AWS_CREDENTIALS=true \
          -e LOCAL_LAMBDA_SERVER_ENABLED=true \
          -e LOCAL_LAMBDA_HOST=0.0.0.0 \
          swift:5.9.2-amazonlinux2 \
          /var/task/bootstrap
        """

        let containerId = try await runShellCommand(startCommand)
        print("  → Container started with ID: \(containerId)")
    }

    private func verifyLambdaRunning() async throws {
        print("🔍 Verifying Lambda is running...")

        // Check container is running
        let containerRunning = try await runShellCommand("docker ps --filter name=lambda-test-container --format '{{.Names}}'")
        #expect(containerRunning.contains("lambda-test-container"), "Lambda container should be running")

        // Wait for Lambda to be ready on the port
        var attempts = 0
        let maxAttempts = 30  // 30 seconds
        var ready = false

        while attempts < maxAttempts && !ready {
            do {
                let portCheck = try await runShellCommand("lsof -i :\(port)")
                if !portCheck.isEmpty {
                    ready = true
                    break
                }
            } catch {
                // Port not ready yet, keep trying
            }

            try await Task.sleep(for: .seconds(1))
            attempts += 1

            if attempts % 10 == 0 {
                print("  → Still waiting for Lambda... (\(attempts) seconds)")
            }
        }

        #expect(ready, "Lambda should be ready on port \(port)")
        print("  ✅ Lambda is running and ready")
    }

    private func stopLambdaContainer() async throws {
        print("🛑 Stopping Lambda container...")
        _ = try await runShellCommand("docker stop lambda-test-container")
        print("  ✅ Lambda container stopped")
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

    // Simple version that doesn't capture output - avoids pipe buffer deadlocks for long-running commands
    private func runShellCommandWithoutCapture(_ command: String, allowNonZeroExit: Bool = false) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = projectRoot

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 && !allowNonZeroExit {
            throw LinuxTestError.commandFailed(
                command: command,
                exitCode: process.terminationStatus,
                output: "",
                error: "Command failed with exit code \(process.terminationStatus)"
            )
        }

        return ""
    }

    private func runShellCommand(_ command: String, allowNonZeroExit: Bool = false) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        // Set working directory to project root
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

        // Combine output and error for build commands (they often use stderr for progress)
        let combinedOutput = output + "\n" + error

        if process.terminationStatus != 0 && !allowNonZeroExit {
            print("❌ Command failed: \(command)")
            print("   Output: \(output)")
            print("   Error: \(error)")
            throw LinuxTestError.commandFailed(
                command: command,
                exitCode: process.terminationStatus,
                output: output,
                error: error
            )
        }

        return combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LinuxTestError: Error, CustomStringConvertible {
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
