import Foundation

/// Service for testing deployed AWS Lambda and infrastructure
public actor AWSTestingService {
    private let awsService: AWSCLIService
    private let cliService: CLIService
    private let stackName = "SwiftLambdaSampleStack"
    private let lambdaName = "swift-lambda-sample"

    public init(awsConfig: AWSAuthConfiguration) {
        self.awsService = AWSCLIService(awsConfig: awsConfig)
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
        let fileName = "hello-world.text"
        let testContent = "Hello World! This data was written/read from S3."

        // Create base64 encoded test data
        guard let data = testContent.data(using: .utf8) else {
            throw CLIError.testFailed(message: "Failed to create test data")
        }
        let base64Data = data.base64EncodedString()

        // Create upload request JSON
        let uploadRequest: [String: String] = [
            "fileName": fileName,
            "data": base64Data
        ]

        guard let uploadJson = try? JSONSerialization.data(withJSONObject: uploadRequest),
              let uploadJsonString = String(data: uploadJson, encoding: .utf8) else {
            throw CLIError.testFailed(message: "Failed to create upload JSON")
        }

        let endpoint = "\(apiUrl)api/files"
        print("→ POST \(endpoint)")
        print("")

        let result = try await cliService.execute(
            command: "curl",
            arguments: [
                "-s",
                "-X", "POST",
                "-H", "Content-Type: application/json",
                "-d", uploadJsonString,
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

        if response.contains("File uploaded") {
            print("✅ File endpoint test passed!")
        } else {
            print("❌ File endpoint test failed!")
            throw CLIError.testFailed(message: "File endpoint did not return expected response. \(result.stderr). \(response)")
        }
    }

    /// Test S3 file endpoint with verbose curl output
    public func testFileEndpointVerbose() async throws {
        print("\n🧪 Testing S3 file endpoint (verbose)...")

        let apiUrl = try await getApiGatewayUrl()
        let fileName = "hello-world.text"
        let testContent = "Hello World! This data was written/read from S3."

        // Create base64 encoded test data
        guard let data = testContent.data(using: .utf8) else {
            throw CLIError.testFailed(message: "Failed to create test data")
        }
        let base64Data = data.base64EncodedString()

        // Create upload request JSON
        let uploadRequest: [String: String] = [
            "fileName": fileName,
            "data": base64Data
        ]

        guard let uploadJson = try? JSONSerialization.data(withJSONObject: uploadRequest),
              let uploadJsonString = String(data: uploadJson, encoding: .utf8) else {
            throw CLIError.testFailed(message: "Failed to create upload JSON")
        }

        let endpoint = "\(apiUrl)api/files"
        print("→ POST \(endpoint)")
        print("")

        _ = try await cliService.execute(
            command: "curl",
            arguments: [
                "-v",
                "-X", "POST",
                "-H", "Content-Type: application/json",
                "-d", uploadJsonString,
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

    /// Test file upload/download with spaces in filename
    public func testFileWithSpaces() async throws {
        print("\n🧪 Testing file upload/download with spaces in filename...")

        let apiUrl = try await getApiGatewayUrl()
        let fileName = "test file with spaces.txt"
        let testContent = "Hello World! This is a test file with spaces in the name."

        // Create base64 encoded test data
        guard let data = testContent.data(using: .utf8) else {
            throw CLIError.testFailed(message: "Failed to create test data")
        }
        let base64Data = data.base64EncodedString()

        // Create upload request JSON
        let uploadRequest: [String: String] = [
            "fileName": fileName,
            "data": base64Data
        ]

        guard let uploadJson = try? JSONSerialization.data(withJSONObject: uploadRequest),
              let uploadJsonString = String(data: uploadJson, encoding: .utf8) else {
            throw CLIError.testFailed(message: "Failed to create upload JSON")
        }

        // Step 1: Upload file
        print("→ Uploading file: \"\(fileName)\"")
        let uploadEndpoint = "\(apiUrl)api/files"

        let uploadResult = try await cliService.execute(
            command: "curl",
            arguments: [
                "-s",
                "-X", "POST",
                "-H", "Content-Type: application/json",
                "-d", uploadJsonString,
                uploadEndpoint
            ],
            printCommand: false
        )

        guard uploadResult.isSuccess else {
            throw CLIError.commandFailed(
                command: "curl",
                exitCode: uploadResult.exitCode,
                stderr: uploadResult.stderr
            )
        }

        print("  Upload response: \(uploadResult.stdout)")

        // Step 2: List files to verify upload
        print("→ Listing files to verify upload...")
        let listEndpoint = "\(apiUrl)api/files"

        let listResult = try await cliService.execute(
            command: "curl",
            arguments: [
                "-s",
                "-X", "GET",
                listEndpoint
            ],
            printCommand: false
        )

        guard listResult.isSuccess else {
            throw CLIError.commandFailed(
                command: "curl",
                exitCode: listResult.exitCode,
                stderr: listResult.stderr
            )
        }

        print("  Files: \(listResult.stdout)")

        guard listResult.stdout.contains(fileName) else {
            throw CLIError.testFailed(message: "Uploaded file '\(fileName)' not found in file list")
        }

        // Step 3: Download file
        print("→ Downloading file: \"\(fileName)\"")

        // URL encode the filename for the download endpoint
        guard let encodedFileName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw CLIError.testFailed(message: "Failed to URL-encode filename")
        }

        let downloadEndpoint = "\(apiUrl)api/files/\(encodedFileName)"

        let downloadResult = try await cliService.execute(
            command: "curl",
            arguments: [
                "-s",
                "-X", "GET",
                downloadEndpoint
            ],
            printCommand: false
        )

        guard downloadResult.isSuccess else {
            throw CLIError.commandFailed(
                command: "curl",
                exitCode: downloadResult.exitCode,
                stderr: downloadResult.stderr
            )
        }

        // Step 4: Verify downloaded content
        print("  Download response: \(downloadResult.stdout)")

        // Parse response as JSON
        guard let responseData = downloadResult.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let downloadedBase64 = json["data"] as? String,
              let downloadedData = Data(base64Encoded: downloadedBase64),
              let downloadedContent = String(data: downloadedData, encoding: .utf8) else {
            throw CLIError.testFailed(message: "Failed to parse download response")
        }

        print("  Downloaded content: \"\(downloadedContent)\"")

        // Verify content matches
        guard downloadedContent == testContent else {
            throw CLIError.testFailed(message: "Downloaded content does not match uploaded content. Expected: '\(testContent)', Got: '\(downloadedContent)'")
        }

        print("✅ File with spaces test passed!")
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

        // Test 2: File with spaces
        do {
            try await testFileWithSpaces()
        } catch {
            print("❌ File with spaces test failed: \(error)")
            allPassed = false
        }

        print("")

        // Test 3: Verify S3
        do {
            try await verifyS3File()
        } catch {
            print("❌ S3 verification failed: \(error)")
            allPassed = false
        }

        print("")

        // Test 4: Check logs
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
