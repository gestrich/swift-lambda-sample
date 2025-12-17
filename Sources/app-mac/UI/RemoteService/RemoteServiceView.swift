import AppKit
import sdk_aws
import sdk_cli
import service_deploy_remote
import SwiftUI

/// View for Remote (AWS) Lambda service management
/// Connects directly to DeploymentModel without going through a separate model layer
struct RemoteServiceView: View {
    @State var service: DeploymentModel

    /// Callback to open settings
    var onOpenSettings: (() -> Void)?

    /// Auxiliary models created from service config
    @State private var githubCIModel: GitHubCIModel?
    @State private var cloudWatchLogsModel: CloudWatchLogsModel?
    @State private var lambdaBuildService: LambdaBuildService?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: - CDK Infrastructure Section
                    cdkInfrastructureSection

                    Divider()

                    // MARK: - Endpoint Section
                    endpointSection

                    Divider()

                    // MARK: - CloudWatch Logs Section
                    cloudWatchLogsSection

                    Divider()

                    // MARK: - Lambda Update Section
                    lambdaUpdateSection
                }
                .padding(20)
            }

            // Collapsible output panel pinned to bottom
            CollapsibleOutputPanel(
                streamProvider: { await service.cliClient.outputStream() },
                streamId: "remote",
                onCommand: { runCommand($0) }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            initializeAuxiliaryModels()
        }
    }

    // MARK: - Auxiliary Model Initialization

    private func initializeAuxiliaryModels() {
        // Create GitHubCIModel if GitHub config is available
        if let githubConfig = GitHubConfiguration.loadConfig() {
            self.githubCIModel = GitHubCIModel(
                projectRoot: service.projectRoot,
                config: githubConfig,
                cliClient: service.cliClient
            )
        }

        // Create CloudWatchLogsModel via workflow
        let workflow = CloudWatchLogsWorkflow.create(
            cliClient: service.cliClient,
            lambdaFunctionName: "swift-lambda-sample",
            credentialProvider: service.awsConfig.makeCredentialProvider()
        )
        self.cloudWatchLogsModel = CloudWatchLogsModel(workflow: workflow)

        // Create LambdaBuildService
        self.lambdaBuildService = LambdaBuildService(
            workingDirectory: service.projectRoot,
            cliClient: service.cliClient,
            awsConfig: service.awsConfig
        )
    }

    // MARK: - CDK Infrastructure Section

    @ViewBuilder
    private var cdkInfrastructureSection: some View {
        CDKInfrastructureSectionView(
            service: service,
            onOpenSettings: onOpenSettings
        )
    }

    // MARK: - Lambda Update Section

    @ViewBuilder
    private var lambdaUpdateSection: some View {
        LambdaUpdateView(
            githubCIModel: githubCIModel,
            lambdaBuildService: lambdaBuildService,
            onOpenSettings: onOpenSettings
        )
    }

    // MARK: - Endpoint Section

    @ViewBuilder
    private var endpointSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("API Gateway")
                    .font(.headline)

                Spacer()

                // Status badge
                remoteStatusBadge

                Button(action: { Task { await service.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh status")
            }

            // Endpoint
            CopyableEndpointView(
                label: "API Gateway URL",
                endpoint: service.state.endpoint,
                helpText: "URL is automatically fetched when refreshing status"
            )
        }
    }

    // MARK: - CloudWatch Logs Section

    @ViewBuilder
    private var cloudWatchLogsSection: some View {
        if let logsModel = cloudWatchLogsModel {
            CloudWatchLogsSectionView(model: logsModel)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("CloudWatch Logs")
                    .font(.headline)
                Text("AWS configuration required")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var remoteStatusBadge: some View {
        HStack(spacing: 4) {
            if service.state.isConfigured {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Connected")
                    .font(.caption2)
                    .foregroundColor(.green)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                Text("Not Configured")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Command Execution

    private func runCommand(_ commandString: String) {
        let parts = commandString.components(separatedBy: " ").filter { !$0.isEmpty }
        guard let command = parts.first else { return }
        let arguments = Array(parts.dropFirst())

        Task {
            _ = try? await service.cliClient.execute(
                command: command,
                arguments: arguments
            )
        }
    }
}

// MARK: - Preview

#Preview {
    // swiftlint:disable:next force_try
    let service = try! DeploymentModel(projectRoot: FileManager.default.currentDirectoryPath)
    return RemoteServiceView(service: service)
        .padding()
        .frame(width: 500)
}
