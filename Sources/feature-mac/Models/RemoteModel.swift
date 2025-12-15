import sdk_cli
import sdk_client
import Combine
import Foundation
import Observation
import service_deploy

/// Observable model for remote AWS Lambda service
/// Holds UI state and delegates operations to services
/// Conforms to LambdaService for polymorphic usage with local services
@MainActor
@Observable
public class RemoteModel: LambdaService {
    private let awsService: AWSCLIService
    public let cliService: CLIService
    private let projectRoot: String

    /// Endpoint fetched from CDK stack (not persisted)
    private var fetchedEndpoint: String?

    // MARK: - Combine Publishers

    private let statusSubject = CurrentValueSubject<DeploymentStatus, Never>(.stopped)
    private let isLoadingStatusSubject = CurrentValueSubject<Bool, Never>(false)

    public var statusPublisher: AnyPublisher<DeploymentStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    public var isLoadingStatusPublisher: AnyPublisher<Bool, Never> {
        isLoadingStatusSubject.eraseToAnyPublisher()
    }

    // MARK: - Sub-Models for UI

    /// GitHub CI model for CI operations. Non-nil if GitHub config is available.
    public private(set) var githubCIModel: GitHubCIModel?

    /// Lambda build service for local builds and uploads. Non-nil if AWS config is available.
    public private(set) var lambdaBuildService: LambdaBuildService?

    /// CloudWatch logs model for viewing Lambda logs. Non-nil if AWS config is available.
    public private(set) var cloudWatchLogsModel: CloudWatchLogsModel?

    // MARK: - CDK Infrastructure State

    /// CDK Infrastructure state (observed from service)
    public private(set) var cdkState: CDKInfrastructureQueryService.State = .unknown

    /// CDK stack name
    public let cdkStackName = CDKStackConfiguration.defaultStackName

    /// Whether CDK infrastructure is configured
    public var isCDKConfigured: Bool { cdkInfrastructureService != nil }

    /// CDK Infrastructure service (private - views use cdkState and action methods)
    private var cdkInfrastructureService: CDKInfrastructureQueryService?

    // MARK: - LambdaService Protocol Properties

    public static let persistenceKey = "remote"

    public static let displayName = "Remote (API Gateway)"

    public static let detailText = "Connect to deployed AWS API Gateway"

    public var port: Int { 443 }

    public var endpoint: String {
        fetchedEndpoint ?? "https://<not-configured>"
    }

    public var endpointLabel: String { "API Gateway URL" }

    public var endpointHelpText: String {
        "URL is automatically fetched when refreshing status"
    }

    public var apiClient: APIClient {
        APIClient(baseURL: endpoint, serviceName: Self.displayName)
    }

    // MARK: - Initialization

    public init(
        projectRoot: String,
        awsConfig: AWSAuthConfiguration,
        cdkDirectory: String = "cdk"
    ) {
        self.projectRoot = projectRoot
        let cliService = CLIService(defaultWorkingDirectory: projectRoot)
        self.cliService = cliService
        self.awsService = AWSCLIService(awsConfig: awsConfig, cliService: cliService)

        // Initialize GitHub CI model if config is available
        if let githubConfig = GitHubConfiguration.loadConfig() {
            self.githubCIModel = GitHubCIModel(repoPath: projectRoot, config: githubConfig, cliService: cliService)
        } else {
            self.githubCIModel = nil
        }

        // Initialize CDK Infrastructure service (AWS config is already available)
        self.cdkInfrastructureService = CDKInfrastructureQueryService(
            projectRoot: projectRoot,
            awsConfig: awsConfig,
            cdkDirectory: cdkDirectory,
            cliService: cliService
        )

        // Initialize Lambda Build service (AWS config is already available)
        self.lambdaBuildService = LambdaBuildService(
            workingDirectory: projectRoot,
            cliService: cliService,
            awsConfig: awsConfig
        )

        // Initialize CloudWatch logs model (AWS config is already available)
        self.cloudWatchLogsModel = CloudWatchLogsModel(
            awsConfig: awsConfig,
            cliService: cliService
        )

        // Start observing CDK state, refresh it, and fetch endpoint
        Task {
            await self.startObservingCDKState()
            await self.cdkInfrastructureService?.refresh()
            try? await self.fetchEndpoint()
        }
    }

    // MARK: - CDK State Observation

    private func startObservingCDKState() async {
        guard let service = cdkInfrastructureService else { return }
        for await state in await service.states() {
            self.cdkState = state
        }
    }

    /// Convenience initializer for workingDirectory-based initialization (matches local services)
    /// Requires AWS config to be available in ~/.swiftSampleDemo/aws-config.json
    public convenience init(workingDirectory: String) {
        let awsConfig = AWSAuthConfiguration.loadConfig() ?? AWSAuthConfiguration(profileName: "default", useAWSVault: false)
        self.init(projectRoot: workingDirectory, awsConfig: awsConfig)
    }

    /// Set the endpoint URL (fetched from CDK, not persisted)
    public func setEndpoint(_ url: String) {
        fetchedEndpoint = url
    }

    public var isConfigured: Bool {
        fetchedEndpoint != nil
    }

    /// Fetch and cache endpoint from CDK stack
    public func fetchEndpoint() async throws {
        let outputs = try await awsService.getStackOutputs(name: "SwiftLambdaSampleStack")
        if let apiUrl = outputs["ApiGatewayUrl"] {
            setEndpoint(apiUrl)
        }
    }

    /// Reload configuration from disk (e.g., after settings are changed)
    /// Only recreates sub-models if configuration has changed or they don't exist yet
    public func reloadConfiguration() {
        // Only reload GitHub CI model if it doesn't exist yet or config changed
        if let githubConfig = GitHubConfiguration.loadConfig() {
            if githubCIModel == nil {
                self.githubCIModel = GitHubCIModel(repoPath: projectRoot, config: githubConfig, cliService: cliService)
            }
        } else {
            self.githubCIModel = nil
        }
    }

    // MARK: - LambdaService Protocol: Testing

    /// Test remote Lambda endpoints
    public func testLambda() async throws {
        let apiUrl = endpoint
        guard !apiUrl.contains("<not-configured>") else {
            throw DeployError.testFailed(message: "Remote endpoint not configured. Deploy first or run fetchEndpoint().")
        }

        print("\n🧪 Testing remote Lambda at \(apiUrl)...")
        print("")

        let client = APIClient(baseURL: apiUrl, serviceName: Self.displayName)

        print("→ Testing file upload...")
        let testContent = "Hello from remote test!"
        guard let testData = testContent.data(using: .utf8) else {
            throw DeployError.testFailed(message: "Failed to create test data")
        }

        let uploadResponse = try await client.uploadFile(fileName: "test-remote.txt", data: testData)
        if uploadResponse.contains("File uploaded: test-remote.txt") {
            print("  ✅ File upload test passed")
        } else {
            print("  ❌ File upload test failed: \(uploadResponse)")
            throw DeployError.testFailed(message: "File upload endpoint test failed")
        }

        print("")

        print("→ Testing list files...")
        let fileList = try await client.listFiles()
        if fileList.contains("test-remote.txt") {
            print("  ✅ List files test passed (found \(fileList.count) files)")
        } else {
            print("  ❌ List files test failed: \(fileList)")
            throw DeployError.testFailed(message: "List files endpoint test failed")
        }

        print("")
        print("✅ All remote Lambda tests passed!")
    }

    /// Wait for Lambda to be ready (check if endpoint responds)
    public func waitForReady(maxAttempts: Int = 30) async throws {
        let apiUrl = endpoint
        guard !apiUrl.contains("<not-configured>") else {
            throw DeployError.testFailed(message: "Remote endpoint not configured")
        }

        print("🔍 Checking remote Lambda availability...")

        var attempts = 0
        var ready = false

        while attempts < maxAttempts && !ready {
            do {
                let curlCommand = Curl.Request.checkStatus(url: "\(apiUrl)api/health")
                let result = try await cliService.executeForResult(curlCommand, printCommand: false)

                if result.isSuccess && (result.stdout == "200" || result.stdout == "404") {
                    ready = true
                    break
                }
            } catch {
                // Ignore errors, keep trying
            }

            try await Task.sleep(for: .seconds(1))
            attempts += 1

            if attempts % 10 == 0 {
                print("  → Still waiting for Lambda... (\(attempts) seconds)")
            }
        }

        if !ready {
            throw DeployError.testFailed(message: "Remote Lambda not responding after \(maxAttempts) seconds")
        }

        print("  ✅ Remote Lambda is available")
    }

    // MARK: - LambdaService Protocol: Status

    /// Get status of remote services
    public func status() async throws -> DeploymentStatus {
        let stackExists = await checkStackExists()

        if stackExists {
            return DeploymentStatus(
                lambdaState: .running,
                s3State: .running,
                postgresState: .running
            )
        } else {
            return DeploymentStatus(
                lambdaState: .stopped,
                s3State: .stopped,
                postgresState: .stopped
            )
        }
    }

    /// Refresh status and publish results via Combine publishers
    /// Always fetches the latest endpoint from CDK stack
    /// Also refreshes GitHub CI and CDK Infrastructure status
    public func refreshStatus() {
        // Reload configuration in case settings were changed
        reloadConfiguration()

        let statusSubject = self.statusSubject
        let isLoadingStatusSubject = self.isLoadingStatusSubject

        isLoadingStatusSubject.send(true)

        // Start all refreshes in parallel using separate Tasks
        if let cdk = cdkInfrastructureService {
            Task { await cdk.refresh() }
        }
        if let github = githubCIModel {
            Task { await github.refreshStatus() }
        }
        Task {
            try? await self.fetchEndpoint()

            do {
                let newStatus = try await self.status()
                statusSubject.send(newStatus)
            } catch {
                statusSubject.send(.stopped)
            }
            isLoadingStatusSubject.send(false)
        }
    }

    // MARK: - CDK Infrastructure Actions

    /// Refresh CDK infrastructure state from AWS
    public func refreshCDKState() {
        Task {
            await cdkInfrastructureService?.refresh()
        }
    }

    /// Deploy CDK infrastructure with specified configuration
    public func deployCDK(withPostgres: Bool, withNATGateway: Bool, output: CLIOutputStream? = nil) {
        Task {
            await cdkInfrastructureService?.deploy(withPostgres: withPostgres, withNATGateway: withNATGateway, output: output)
        }
    }

    /// Update CDK infrastructure maintaining current configuration
    public func updateCDKInfrastructure(output: CLIOutputStream? = nil) {
        Task {
            await cdkInfrastructureService?.updateInfrastructure(output: output)
        }
    }

    /// Destroy CDK infrastructure
    public func destroyCDK(output: CLIOutputStream? = nil) {
        Task {
            await cdkInfrastructureService?.destroy(output: output)
        }
    }

    // MARK: - Private Helpers

    private func checkStackExists() async -> Bool {
        do {
            let outputs = try await awsService.getStackOutputs(name: "SwiftLambdaSampleStack")
            return !outputs.isEmpty
        } catch {
            return false
        }
    }
}
