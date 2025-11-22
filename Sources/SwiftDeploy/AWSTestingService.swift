import Foundation

/// Service for testing deployed AWS Lambda and infrastructure
public actor AWSTestingService {
    private let awsService: AWSCLIService
    private let cliService: CLIService
    private let stackName = "SwiftLambdaSampleStack"
    private let lambdaName = "swift-lambda-sample"

    public init(awsProfile: String) {
        self.awsService = AWSCLIService(profile: awsProfile)
        self.cliService = CLIService.shared
    }

    // MARK: - API Gateway

    /// Get API Gateway URL from CloudFormation stack outputs
    public func getApiGatewayUrl() async throws -> String {
        return try await awsService.getStackOutput(stackName: stackName, outputKey: "ApiGatewayUrl")
    }

    // MARK: - S3 Testing

    /// Test S3 file upload/download endpoint
    public func testFileEndpoint() async throws {
        print("\n🧪 Testing S3 file endpoint...")

        let apiUrl = try await getApiGatewayUrl()
        let endpoint = "\(apiUrl)api/file"

        print("→ POST \(endpoint)")
        print("")

        let result = try await cliService.execute(
            command: "curl",
            arguments: [
                "-s",
                "-X", "POST",
                endpoint
            ],
            printCommand: false
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "curl",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        let response = result.stdout
        print("Response: \(response)")

        if response.contains("File uploaded and downloaded") {
            print("✅ File endpoint test passed!")
        } else {
            print("❌ File endpoint test failed!")
            throw CLIError.testFailed(message: "File endpoint did not return expected response")
        }
    }

    /// Test S3 file endpoint with verbose curl output
    public func testFileEndpointVerbose() async throws {
        print("\n🧪 Testing S3 file endpoint (verbose)...")

        let apiUrl = try await getApiGatewayUrl()
        let endpoint = "\(apiUrl)api/file"

        print("→ POST \(endpoint)")
        print("")

        _ = try await cliService.execute(
            command: "curl",
            arguments: [
                "-v",
                "-X", "POST",
                endpoint
            ]
        )
    }

    /// Verify S3 file was created and show content
    public func verifyS3File() async throws {
        print("\n🔍 Verifying S3 file creation...")

        // Get bucket name from stack outputs
        let bucketName = try await awsService.getStackOutput(stackName: stackName, outputKey: "BucketName")

        print("Bucket: \(bucketName)")
        print("")

        // List files in bucket
        print("Files in bucket:")
        let files = try await awsService.s3List(bucket: bucketName)
        print(files)
        print("")

        // Get file content
        print("Content of hello-world.text:")
        let content = try await awsService.s3Copy(
            source: "s3://\(bucketName)/hello-world.text",
            destination: "-"
        )
        print(content)
        print("")
    }

    // MARK: - Logging

    /// Check Lambda execution logs
    public func checkLogs(since: String = "5m") async throws {
        print("\n📋 Lambda execution logs (last \(since)):")

        try await awsService.tailLogs(
            logGroup: "/aws/lambda/\(lambdaName)",
            since: since,
            format: "short"
        )
    }

    // MARK: - Comprehensive Testing

    /// Run all deployment verification tests
    public func runAllTests() async throws {
        print("\n🚀 Running deployment verification tests...")
        print("")

        var allPassed = true

        // Test 1: File endpoint
        do {
            try await testFileEndpoint()
        } catch {
            print("❌ File endpoint test failed: \(error)")
            allPassed = false
        }

        print("")

        // Test 2: Verify S3
        do {
            try await verifyS3File()
        } catch {
            print("❌ S3 verification failed: \(error)")
            allPassed = false
        }

        print("")

        // Test 3: Check logs
        do {
            try await checkLogs(since: "5m")
        } catch {
            print("❌ Log check failed: \(error)")
            allPassed = false
        }

        print("")
        print("================================")

        if allPassed {
            print("✅ All tests passed!")
        } else {
            print("❌ Some tests failed")
            throw CLIError.testFailed(message: "One or more deployment tests failed")
        }
    }
}
