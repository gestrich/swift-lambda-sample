import Foundation
import sdk_aws
import sdk_cli
import sdk_github
import service_deploy_core

/// Workflow for initial deployment - setting infrastructure configuration.
/// Orchestrates safety checks, CDK deployment, Lambda update, database init, and verification.
public struct DeployInitWorkflow: Sendable {
    private let deployComponents: DeployWorkflow.Components
    private let cliClient: CLIClient
    private let projectRoot: String

    public init(
        deployComponents: DeployWorkflow.Components,
        cliClient: CLIClient,
        projectRoot: String
    ) {
        self.deployComponents = deployComponents
        self.cliClient = cliClient
        self.projectRoot = projectRoot
    }

    /// Components needed for deploy-init operations.
    public struct Components: Sendable {
        public let workflow: DeployInitWorkflow
        public let cfClient: CloudFormationClient
        public let stackName: String
    }

    /// Creates a workflow and associated components by instantiating required clients.
    /// - Parameters:
    ///   - cdkDirectory: Full path to the CDK directory
    ///   - credentialProvider: AWS credential provider for authentication
    ///   - cliClient: CLI client for executing commands
    ///   - projectRoot: Root directory of the project
    ///   - stackName: CloudFormation stack name (defaults to CDKStackConfiguration.defaultStackName)
    /// - Returns: Components containing the workflow and CloudFormation client
    public static func create(
        cdkDirectory: String,
        credentialProvider: any AWSCredentialProvider,
        cliClient: CLIClient,
        projectRoot: String,
        stackName: String = CDKStackConfiguration.defaultStackName
    ) -> Components {
        let deployComponents = DeployWorkflow.create(
            cdkDirectory: cdkDirectory,
            credentialProvider: credentialProvider,
            cliClient: cliClient,
            stackName: stackName
        )

        let workflow = DeployInitWorkflow(
            deployComponents: deployComponents,
            cliClient: cliClient,
            projectRoot: projectRoot
        )

        return Components(
            workflow: workflow,
            cfClient: deployComponents.cfClient,
            stackName: deployComponents.stackName
        )
    }

    /// Progress updates from the deploy-init workflow.
    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checkingSafety
            case checkingConfiguration
            case deployingInfrastructure
            case updatingLambda
            case initializingDatabase
            case verifyingDeployment
            case complete
        }

        public enum Detail: Sendable {
            case safetyCheckPassed
            case existingConfiguration(ExistingConfiguration)
            case deployProgress(WorkflowState)
            case lambdaProgress(WorkflowState)
            case databaseResponse(String)
            case healthCheckResponse(String)
            case outputs(CDKStackOutputs?)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    /// Existing stack configuration detected during safety/configuration checks
    public struct ExistingConfiguration: Sendable {
        public let hasDatabase: Bool
        public let hasNATGateway: Bool

        public init(hasDatabase: Bool, hasNATGateway: Bool) {
            self.hasDatabase = hasDatabase
            self.hasNATGateway = hasNATGateway
        }
    }

    /// Options for the deploy-init workflow.
    public struct Options: Sendable {
        public let withPostgres: Bool
        public let withNATGateway: Bool
        public let skipPush: Bool

        public init(
            withPostgres: Bool = false,
            withNATGateway: Bool = false,
            skipPush: Bool = false
        ) {
            self.withPostgres = withPostgres
            self.withNATGateway = withNATGateway
            self.skipPush = skipPush
        }
    }

    /// Run the deploy-init workflow.
    public func run(options: Options) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(options: options, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        options: Options,
        continuation: AsyncThrowingStream<Progress, Error>.Continuation
    ) async throws {
        let cfClient = deployComponents.cfClient
        let stackName = deployComponents.stackName

        // Phase 1: Safety check - prevent accidental database deletion
        continuation.yield(Progress(step: .checkingSafety))
        try await checkDatabaseSafety(
            cfClient: cfClient,
            stackName: stackName,
            withPostgres: options.withPostgres
        )
        continuation.yield(Progress(step: .checkingSafety, detail: .safetyCheckPassed))

        // Phase 2: Check and report existing configuration
        continuation.yield(Progress(step: .checkingConfiguration))
        if let existingConfig = try await checkExistingConfiguration(
            cfClient: cfClient,
            stackName: stackName
        ) {
            continuation.yield(Progress(
                step: .checkingConfiguration,
                detail: .existingConfiguration(existingConfig)
            ))
        }

        // Phase 3: Deploy infrastructure
        continuation.yield(Progress(step: .deployingInfrastructure))
        let deployOptions = DeployWorkflow.Options(
            withPostgres: options.withPostgres,
            withNATGateway: options.withNATGateway
        )

        var apiUrl: String?
        var finalOutputs: CDKStackOutputs?

        for try await workflowState in deployComponents.workflow.run(options: deployOptions) {
            continuation.yield(Progress(
                step: .deployingInfrastructure,
                detail: .deployProgress(workflowState)
            ))

            if case .completed(let snapshot) = workflowState {
                finalOutputs = snapshot.outputs
                apiUrl = snapshot.apiGatewayUrl
            }
        }

        guard let apiUrl else {
            throw DeployError.deploymentFailed(reason: "Could not find ApiGatewayUrl in stack outputs")
        }

        // Phase 4: Update Lambda code via GitHub Actions
        continuation.yield(Progress(step: .updatingLambda))
        let updateLambdaWorkflow = try UpdateLambdaWorkflow.create(
            projectRoot: projectRoot,
            cliClient: cliClient
        )
        let updateOptions = UpdateLambdaWorkflow.Options(skipPush: options.skipPush)

        for try await lambdaState in updateLambdaWorkflow.run(options: updateOptions) {
            continuation.yield(Progress(
                step: .updatingLambda,
                detail: .lambdaProgress(lambdaState)
            ))
        }

        // Phase 5: Initialize database if Postgres is included
        if options.withPostgres {
            continuation.yield(Progress(step: .initializingDatabase))
            let response = try await initializeDatabase(apiUrl: apiUrl)
            continuation.yield(Progress(
                step: .initializingDatabase,
                detail: .databaseResponse(response)
            ))
        }

        // Phase 6: Verify deployment
        continuation.yield(Progress(step: .verifyingDeployment))
        let healthResponse = try await verifyDeployment(apiUrl: apiUrl)
        continuation.yield(Progress(
            step: .verifyingDeployment,
            detail: .healthCheckResponse(healthResponse)
        ))

        // Complete
        continuation.yield(Progress(step: .complete, detail: .outputs(finalOutputs)))
        continuation.finish()
    }

    // MARK: - Private Helpers

    private func checkDatabaseSafety(
        cfClient: CloudFormationClient,
        stackName: String,
        withPostgres: Bool
    ) async throws {
        do {
            let state = try await cfClient.queryState(stackName: stackName)

            if case .deployed = state {
                let resources = try await cfClient.describeStackResources(name: stackName)
                let hasExistingDatabase = resources.contains {
                    $0.logicalResourceId.contains("Database") && $0.resourceType.contains("RDS")
                }

                if hasExistingDatabase && !withPostgres {
                    throw DeployError.invalidConfiguration(
                        "Cannot remove database with deploy-init. Use 'tear-down' first if you want to remove the database."
                    )
                }
            }
        } catch let error as DeployError {
            throw error
        } catch {
            // Stack doesn't exist or other error - safe to proceed
        }
    }

    private func checkExistingConfiguration(
        cfClient: CloudFormationClient,
        stackName: String
    ) async throws -> ExistingConfiguration? {
        do {
            let state = try await cfClient.queryState(stackName: stackName)

            if case .deployed = state {
                let resources = try await cfClient.describeStackResources(name: stackName)
                return ExistingConfiguration(
                    hasDatabase: resources.hasDatabase,
                    hasNATGateway: resources.hasNATGateway
                )
            }
        } catch {
            // Stack doesn't exist - that's fine for deploy-init
        }
        return nil
    }

    private func initializeDatabase(apiUrl: String) async throws -> String {
        let curlCommand = Curl.Request.post(url: "\(apiUrl)api/database", silent: true)
        let result = try await cliClient.executeForResult(curlCommand, printCommand: false)

        if !result.isSuccess {
            let errorOutput = result.stderr.isEmpty ? result.stdout : result.stderr
            throw DeployError.commandFailed(
                command: "curl POST /api/database",
                exitCode: result.exitCode,
                output: errorOutput
            )
        }

        let response = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if !response.contains("Database Initialized") {
            throw DeployError.deploymentFailed(reason: "Unexpected database init response: \(response)")
        }

        return response
    }

    private func verifyDeployment(apiUrl: String) async throws -> String {
        let healthCommand = Curl.Request.get(url: "\(apiUrl)api/health", silent: true)
        let testResult = try await cliClient.executeForResult(healthCommand, printCommand: false)

        if !testResult.isSuccess {
            let errorOutput = testResult.stderr.isEmpty ? testResult.stdout : testResult.stderr
            throw DeployError.testFailed(message: "Health check failed: \(errorOutput)")
        }

        let healthResponse = testResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if healthResponse.contains("error") || healthResponse.contains("Error") {
            throw DeployError.testFailed(message: "Health check returned error: \(healthResponse)")
        }

        return healthResponse
    }
}
