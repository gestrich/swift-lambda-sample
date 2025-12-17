import AppKit
import sdk_cli
import service_deploy_remote
import SwiftUI

/// View for Local Lambda service management (Xcode or Linux)
/// Shows Docker services, build controls, and Lambda management
/// The service mode (Xcode vs Linux) is controlled by the parent ServicesView
struct LocalServiceView: View {
    let service: LocalServicesModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: - Docker Services Section
                    DockerServicesView(
                        dockerProvider: service,
                        s3State: service.status.s3State,
                        postgresState: service.status.postgresState,
                        dynamodbState: service.status.dynamodbState,
                        onRefreshStatus: { service.refreshStatus() }
                    )

                    Divider()

                    // MARK: - Build Section
                    buildSection

                    Divider()

                    // MARK: - Lambda Section
                    lambdaSection
                }
                .padding(20)
            }

            // Collapsible output panel pinned to bottom
            CollapsibleOutputPanel(
                streamProvider: { await service.cliClient.outputStream() },
                streamId: type(of: service).persistenceKey,
                onCommand: { runCommand($0) }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            service.refreshStatus()
        }
    }

    // MARK: - Build Section

    @ViewBuilder
    private var buildSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Build")
                    .font(.headline)

                Spacer()

                // Build status badge
                buildStatusBadge
            }

            OperationOutputSection { stream, showOutput in
                HStack {
                    Button(action: {
                        showOutput()
                        Task {
                            try? await service.build(clean: false, output: stream)
                        }
                    }) {
                        if service.buildState.status.isBuilding {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "hammer")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(service.buildState.status.isBuilding)
                    .help("Build Lambda")

                    Button(action: {
                        showOutput()
                        Task {
                            try? await service.build(clean: true, output: stream)
                        }
                    }) {
                        Image(systemName: "sparkles")
                    }
                    .buttonStyle(.borderless)
                    .disabled(service.buildState.status.isBuilding)
                    .help("Clean and Build Lambda")

                    if service.buildState.status.hasArtifact {
                        Button(action: {
                            Task {
                                try? await service.deleteBuild()
                            }
                        }) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(service.buildState.status.isBuilding)
                        .help("Delete Build")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var buildStatusBadge: some View {
        let status = service.buildState.status
        HStack(spacing: 4) {
            if status.showProgress {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Image(systemName: status.iconName)
                    .foregroundColor(buildStatusColor)
            }
            Text(status.displayText)
                .font(.caption2)
                .foregroundColor(buildStatusColor)
        }
    }

    private var buildStatusColor: Color {
        switch service.buildState.status.colorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "secondary": return .secondary
        default: return .primary
        }
    }

    // MARK: - Lambda Section

    @ViewBuilder
    private var lambdaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("API Gateway")
                    .font(.headline)

                Spacer()

                // Lambda status badge
                lambdaStatusBadge
            }

            OperationOutputSection { stream, showOutput in
                HStack {
                    Button(action: {
                        showOutput()
                        Task {
                            try? await service.startWithServices(output: stream)
                        }
                    }) {
                        if service.lambdaState.status.isTransitioning {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "play.circle")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(service.lambdaState.status.isTransitioning)
                    .help("Start Lambda")

                    Button(action: {
                        showOutput()
                        Task {
                            try? await service.stopWithServices(output: stream)
                        }
                    }) {
                        Image(systemName: "stop.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(service.lambdaState.status.isTransitioning || service.lambdaState.status == .stopped)
                    .help("Stop Lambda")

                    Button(action: { service.refreshStatus() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(service.lambdaState.status.isTransitioning)
                    .help("Refresh status")
                }
            }

            // Endpoint
            CopyableEndpointView(
                label: "Endpoint",
                endpoint: service.endpoint,
                helpText: service.endpointHelpText
            )
        }
    }

    @ViewBuilder
    private var lambdaStatusBadge: some View {
        let status = service.lambdaState.status
        HStack(spacing: 4) {
            if status.showProgress {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Image(systemName: status.iconName)
                    .foregroundColor(lambdaStatusColor)
            }
            Text(status.displayText)
                .font(.caption2)
                .foregroundColor(lambdaStatusColor)
        }
    }

    private var lambdaStatusColor: Color {
        switch service.lambdaState.status.colorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "secondary": return .secondary
        default: return .primary
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
