//
//  AWSIntegrationTests.swift
//  SwiftDeploy
//
//  Integration tests for deployed AWS Lambda and infrastructure.
//  These tests require valid AWS credentials and a deployed stack.
//

import Foundation
import d_sdk_aws
import d_sdk_cli
import c_service_client
@testable import c_service_deploy_remote
import Testing

@Suite("AWS Integration Tests", .disabled("Requires deployed AWS infrastructure and credentials"))
@MainActor
struct AWSIntegrationTests {

    let cloudFormationClient: CloudFormationClient
    let cloudWatchLogsClient: CloudWatchLogsClient
    let s3Client: S3Client
    let credentialProvider: AWSCredentialProvider
    let cliClient: CLIClient
    let stackName = CDKStackConfiguration.defaultStackName
    let lambdaLogGroup = "/aws/lambda/swift-lambda-sample"

    init() throws {
        guard let awsConfig = AWSAuthConfiguration.loadConfig() else {
            throw TestError.missingConfiguration("AWS config not found at ~/.swiftSampleDemo/aws-config.json")
        }

        self.cliClient = CLIClient()
        self.credentialProvider = awsConfig.makeCredentialProvider()
        self.cloudFormationClient = CloudFormationClient(
            credentialProvider: credentialProvider,
            cliClient: cliClient
        )
        self.cloudWatchLogsClient = CloudWatchLogsClient(cliClient: cliClient)
        self.s3Client = S3Client(credentialProvider: credentialProvider, cliClient: cliClient)
    }

    // MARK: - API Gateway Tests

    @Test("Get API Gateway URL from CloudFormation outputs")
    func testGetApiGatewayUrl() async throws {
        let url = try await cloudFormationClient.getStackOutput(
            stackName: stackName,
            outputKey: "ApiGatewayUrl"
        )

        #expect(!url.isEmpty, "API Gateway URL should not be empty")
        #expect(url.hasPrefix("https://"), "API Gateway URL should be HTTPS")
        print("API Gateway URL: \(url)")
    }

    // MARK: - S3 Tests

    @Test("S3 file upload and download via API")
    func testFileEndpoint() async throws {
        let apiUrl = try await cloudFormationClient.getStackOutput(
            stackName: stackName,
            outputKey: "ApiGatewayUrl"
        )

        let fileName = "hello-world.text"
        let testContent = "Hello World! This data was written/read from S3."

        guard let data = testContent.data(using: .utf8) else {
            throw TestError.testFailed("Failed to create test data")
        }

        let baseURL = apiUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let client = APIClient(baseURL: baseURL, serviceName: "AWS")

        print("Testing S3 file endpoint...")
        print("POST \(baseURL)/api/files")

        let response = try await client.uploadFile(fileName: fileName, data: data)

        #expect(response.contains("File uploaded"), "Expected upload success message, got: \(response)")
        print("S3 file upload test passed")
    }

    @Test("S3 file upload and download with spaces in filename")
    func testFileWithSpaces() async throws {
        let apiUrl = try await cloudFormationClient.getStackOutput(
            stackName: stackName,
            outputKey: "ApiGatewayUrl"
        )

        let fileName = "test file with spaces.txt"
        let testContent = "Hello World! This is a test file with spaces in the name."

        guard let data = testContent.data(using: .utf8) else {
            throw TestError.testFailed("Failed to create test data")
        }

        let baseURL = apiUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let client = APIClient(baseURL: baseURL, serviceName: "AWS")

        // Upload
        print("Uploading file: \"\(fileName)\"")
        let uploadResponse = try await client.uploadFile(fileName: fileName, data: data)
        print("Upload response: \(uploadResponse)")

        // List to verify
        print("Listing files to verify upload...")
        let fileList = try await client.listFiles()
        #expect(fileList.contains(fileName), "Uploaded file '\(fileName)' not found in file list")

        // Download
        print("Downloading file: \"\(fileName)\"")
        let downloadedData = try await client.downloadFile(fileName: fileName)

        guard let downloadedContent = String(data: downloadedData, encoding: .utf8) else {
            throw TestError.testFailed("Failed to decode downloaded content")
        }

        #expect(downloadedContent == testContent, "Content mismatch. Expected: '\(testContent)', Got: '\(downloadedContent)'")
        print("File with spaces test passed")
    }

    @Test("Verify S3 file exists in bucket")
    func testVerifyS3File() async throws {
        let bucketName = try await cloudFormationClient.getStackOutput(
            stackName: stackName,
            outputKey: "BucketName"
        )

        print("Bucket: \(bucketName)")

        let files = try await s3Client.listRaw(bucket: bucketName)
        #expect(!files.isEmpty, "Bucket should contain files")
        print("Files in bucket: \(files)")

        let content = try await s3Client.copy(
            source: "s3://\(bucketName)/hello-world.text",
            destination: "-"
        )
        #expect(!content.isEmpty, "File content should not be empty")
        print("Content of hello-world.text: \(content)")
    }

    // MARK: - User Endpoint Tests

    @Test("User CRUD endpoints (requires PostgreSQL)")
    func testUserEndpoints() async throws {
        let apiUrl = try await cloudFormationClient.getStackOutput(
            stackName: stackName,
            outputKey: "ApiGatewayUrl"
        )

        let baseURL = apiUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let client = APIClient(baseURL: baseURL, serviceName: "AWS")

        print("GET \(baseURL)/api/users")
        let users = try await client.listUsers()
        print("Found \(users.count) users")

        // Test passes if we get a response (connection working)
        print("User endpoint test passed - database connection working")
    }

    // MARK: - CloudWatch Logs Tests

    @Test("Fetch Lambda CloudWatch logs")
    func testCheckLogs() async throws {
        print("Fetching Lambda logs from last 5m...")

        _ = try await cloudWatchLogsClient.fetchLogs(
            logGroup: lambdaLogGroup,
            since: "5m",
            credentialProvider: credentialProvider
        )

        // Test passes if no error thrown
        print("CloudWatch logs fetch successful")
    }

    // MARK: - Full Integration Test

    @Test("Run all deployment verification tests")
    func testFullDeploymentVerification() async throws {
        print("Running full deployment verification...")

        // Test API Gateway URL
        let apiUrl = try await cloudFormationClient.getStackOutput(
            stackName: stackName,
            outputKey: "ApiGatewayUrl"
        )
        #expect(!apiUrl.isEmpty)

        // Test S3 file endpoint
        let baseURL = apiUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let client = APIClient(baseURL: baseURL, serviceName: "AWS")

        let testContent = "Integration test content"
        guard let data = testContent.data(using: .utf8) else {
            throw TestError.testFailed("Failed to create test data")
        }

        let response = try await client.uploadFile(fileName: "integration-test.txt", data: data)
        #expect(response.contains("File uploaded"))

        // Verify S3 bucket
        let bucketName = try await cloudFormationClient.getStackOutput(
            stackName: stackName,
            outputKey: "BucketName"
        )
        let files = try await s3Client.listRaw(bucket: bucketName)
        #expect(!files.isEmpty)

        print("Full deployment verification passed")
    }
}

// MARK: - Test Errors

enum TestError: Error, LocalizedError {
    case missingConfiguration(String)
    case testFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let message):
            return "Missing configuration: \(message)"
        case .testFailed(let message):
            return "Test failed: \(message)"
        }
    }
}
