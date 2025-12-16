import Foundation
import sdk_aws
import sdk_cli
import sdk_client

/// Service for testing deployed AWS Lambda and infrastructure
public actor AWSTestingService {
    private let cloudFormationClient: CloudFormationClient
    private let cloudWatchLogsClient: CloudWatchLogsClient
    private let s3Client: S3Client
    private let cliClient: CLIClient
    private let stackName = CDKStackConfiguration.defaultStackName
    private let lambdaName = "swift-lambda-sample"

    public init(awsConfig: AWSAuthConfiguration, cliClient: CLIClient) {
        self.cliClient = cliClient
        let credentialProvider = awsConfig.makeCredentialProvider()
        self.cloudFormationClient = CloudFormationClient(
            credentialProvider: credentialProvider,
            cliClient: cliClient
        )
        self.cloudWatchLogsClient = CloudWatchLogsClient(
            logGroup: "/aws/lambda/swift-lambda-sample",
            credentialProvider: credentialProvider,
            cliClient: cliClient
        )
        self.s3Client = S3Client(credentialProvider: credentialProvider, cliClient: cliClient)
    }

    /// Convenience initializer that creates its own CLIClient
    public init(awsConfig: AWSAuthConfiguration) {
        let cliClient = CLIClient()
        self.cliClient = cliClient
        let credentialProvider = awsConfig.makeCredentialProvider()
        self.cloudFormationClient = CloudFormationClient(
            credentialProvider: credentialProvider,
            cliClient: cliClient
        )
        self.cloudWatchLogsClient = CloudWatchLogsClient(
            logGroup: "/aws/lambda/swift-lambda-sample",
            credentialProvider: credentialProvider,
            cliClient: cliClient
        )
        self.s3Client = S3Client(credentialProvider: credentialProvider, cliClient: cliClient)
    }

    /// Create an API client configured with the deployed API Gateway URL
    @MainActor
    private func createAPIClient() async throws -> APIClient {
        let apiUrl = try await getApiGatewayUrl()
        let baseURL = apiUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return APIClient(baseURL: baseURL, serviceName: "AWS")
    }

    // MARK: - API Gateway

    /// Get API Gateway URL from CloudFormation stack outputs
    public func getApiGatewayUrl() async throws -> String {
        return try await cloudFormationClient.getStackOutput(stackName: stackName, outputKey: "ApiGatewayUrl")
    }

    // MARK: - S3 Testing

    /// Test S3 file upload/download endpoint
    public func testFileEndpoint() async throws {
        print("\n🧪 Testing S3 file endpoint...")

        let apiUrl = try await getApiGatewayUrl()
        let fileName = "hello-world.text"
        let testContent = "Hello World! This data was written/read from S3."

        guard let data = testContent.data(using: .utf8) else {
            throw DeployError.testFailed(message: "Failed to create test data")
        }

        let endpoint = "\(apiUrl)api/files"
        print("→ POST \(endpoint)")
        print("")

        do {
            let response = try await performFileUpload(fileName: fileName, data: data)

            print("Response: \(response)")

            if response.contains("File uploaded") {
                print("✅ File endpoint test passed!")
            } else {
                print("❌ File endpoint test failed!")
                throw DeployError.testFailed(message: "File endpoint did not return expected response: \(response)")
            }
        } catch let error as APIError {
            throw DeployError.testFailed(message: "API Error: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func performFileUpload(fileName: String, data: Data) async throws -> String {
        let client = try await createAPIClient()
        return try await client.uploadFile(fileName: fileName, data: data)
    }

    /// Test S3 file endpoint with verbose curl output
    public func testFileEndpointVerbose() async throws {
        print("\n🧪 Testing S3 file endpoint (verbose)...")

        let apiUrl = try await getApiGatewayUrl()
        let fileName = "hello-world.text"
        let testContent = "Hello World! This data was written/read from S3."

        // Create base64 encoded test data
        guard let data = testContent.data(using: .utf8) else {
            throw DeployError.testFailed(message: "Failed to create test data")
        }
        let base64Data = data.base64EncodedString()

        // Create upload request JSON
        let uploadRequest: [String: String] = [
            "fileName": fileName,
            "data": base64Data
        ]

        guard let uploadJson = try? JSONSerialization.data(withJSONObject: uploadRequest),
              let uploadJsonString = String(data: uploadJson, encoding: .utf8) else {
            throw DeployError.testFailed(message: "Failed to create upload JSON")
        }

        let endpoint = "\(apiUrl)api/files"
        print("→ POST \(endpoint)")
        print("")

        let curlCommand = Curl.Request.postJSON(url: endpoint, data: uploadJsonString, verbose: true)
        _ = try await cliClient.execute(curlCommand)
    }

    /// Verify S3 file was created and show content
    public func verifyS3File() async throws {
        print("\n🔍 Verifying S3 file creation...")

        // Get bucket name from stack outputs
        let bucketName = try await cloudFormationClient.getStackOutput(stackName: stackName, outputKey: "BucketName")

        print("Bucket: \(bucketName)")
        print("")

        // List files in bucket
        print("Files in bucket:")
        let files = try await s3Client.listRaw(bucket: bucketName)
        print(files)
        print("")

        // Get file content
        print("Content of hello-world.text:")
        let content = try await s3Client.copy(
            source: "s3://\(bucketName)/hello-world.text",
            destination: "-"
        )
        print(content)
        print("")
    }

    /// Test file upload/download with spaces in filename
    public func testFileWithSpaces() async throws {
        print("\n🧪 Testing file upload/download with spaces in filename...")

        let fileName = "test file with spaces.txt"
        let testContent = "Hello World! This is a test file with spaces in the name."

        guard let data = testContent.data(using: .utf8) else {
            throw DeployError.testFailed(message: "Failed to create test data")
        }

        do {
            try await performFileWithSpacesTest(fileName: fileName, data: data, expectedContent: testContent)
        } catch let error as APIError {
            throw DeployError.testFailed(message: "API Error: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func performFileWithSpacesTest(fileName: String, data: Data, expectedContent: String) async throws {
        let client = try await createAPIClient()

        // Step 1: Upload file
        print("→ Uploading file: \"\(fileName)\"")
        let uploadResponse = try await client.uploadFile(fileName: fileName, data: data)
        print("  Upload response: \(uploadResponse)")

        // Step 2: List files to verify upload
        print("→ Listing files to verify upload...")
        let fileList = try await client.listFiles()
        print("  Files: \(fileList)")

        guard fileList.contains(fileName) else {
            throw DeployError.testFailed(message: "Uploaded file '\(fileName)' not found in file list")
        }

        // Step 3: Download file
        print("→ Downloading file: \"\(fileName)\"")
        let downloadedData = try await client.downloadFile(fileName: fileName)

        // Step 4: Verify downloaded content
        guard let downloadedContent = String(data: downloadedData, encoding: .utf8) else {
            throw DeployError.testFailed(message: "Failed to decode downloaded content")
        }

        print("  Downloaded content: \"\(downloadedContent)\"")

        // Verify content matches
        guard downloadedContent == expectedContent else {
            throw DeployError.testFailed(message: "Downloaded content does not match uploaded content. Expected: '\(expectedContent)', Got: '\(downloadedContent)'")
        }

        print("✅ File with spaces test passed!")
    }

    // MARK: - User Testing

    /// Test user CRUD endpoints (requires PostgreSQL)
    public func testUserEndpoints() async throws {
        print("🧪 Testing user endpoints...\n")

        do {
            try await performUserEndpointTest()
        } catch let error as APIError {
            throw DeployError.testFailed(message: "API Error: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func performUserEndpointTest() async throws {
        let client = try await createAPIClient()

        // Test GET /api/users
        print("→ GET \(client.baseURL)/api/users")
        let users = try await client.listUsers()
        print("Response: Found \(users.count) users\n")

        print("✅ User endpoint test passed")
        print("✓ Database connection working")
        print("✓ User endpoint responding with valid data")
    }

    // MARK: - Logging

    /// Check Lambda execution logs
    public func checkLogs(since: String = "5m") async throws {
        print("\n📋 Lambda execution logs (last \(since)):")

        _ = try await cloudWatchLogsClient.fetchRecentLogs(since: since)
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
            throw DeployError.testFailed(message: "One or more deployment tests failed")
        }
    }
}
