import AppKit
import CLIKit
import SwiftDeploy
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
                        onRefreshStatus: { service.refreshStatus() }
                    )

                    Divider()

                    // MARK: - Build Section
                    buildSection

                    Divider()

                    // MARK: - Lambda Section
                    lambdaSection

                    Divider()

                    // MARK: - Sample Data Section
                    sampleDataSection
                }
                .padding(20)
            }

            Divider()

            // Output and command input pinned to bottom
            VStack(alignment: .leading, spacing: 8) {
                outputSection
                commandInputSection
            }
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
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

                Button(action: {
                    Task {
                        try? await service.build(clean: false)
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
                    Task {
                        try? await service.build(clean: true)
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
                Text("Lambda")
                    .font(.headline)

                Spacer()

                // Lambda status badge
                lambdaStatusBadge

                Button(action: {
                    Task {
                        try? await service.startWithServices()
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
                    Task {
                        try? await service.stopWithServices()
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

            // Endpoint
            VStack(alignment: .leading, spacing: 5) {
                Text("Endpoint")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Endpoint", text: .constant(service.endpoint))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Text(service.endpointHelpText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
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

    // MARK: - Sample Data Section

    @State private var isCreatingSampleUser = false
    @State private var sampleUserResult: String?

    @ViewBuilder
    private var sampleDataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sample Data")
                .font(.headline)

            HStack {
                Button(action: {
                    Task {
                        isCreatingSampleUser = true
                        sampleUserResult = nil
                        do {
                            let user = try await service.createSampleUser()
                            sampleUserResult = "Created: \(user.firstName) \(user.lastName) (\(user.nickName))"
                        } catch {
                            sampleUserResult = "Error: \(error.localizedDescription)"
                        }
                        isCreatingSampleUser = false
                    }
                }) {
                    if isCreatingSampleUser {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Label("Create Sample User", systemImage: "person.badge.plus")
                    }
                }
                .disabled(isCreatingSampleUser)

                Spacer()
            }

            if let result = sampleUserResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(result.hasPrefix("Error") ? .red : .green)
            }
        }
    }

    // MARK: - Output Section

    @ViewBuilder
    private var outputSection: some View {
        let cliService = service.cliService
        let persistenceKey = type(of: service).persistenceKey
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.headline)

            StreamingTextView(streamProvider: { await cliService.outputStream() })
                .id(persistenceKey)
        }
    }

    // MARK: - Command Input Section

    @State private var commandText = ""

    @ViewBuilder
    private var commandInputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            CommandInputView(text: $commandText) { command in
                runCommand(command)
            }

            Text("Type a command and press Enter. Tab to autocomplete, arrows to navigate.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func runCommand(_ commandString: String) {
        let parts = commandString.components(separatedBy: " ").filter { !$0.isEmpty }
        guard let command = parts.first else { return }
        let arguments = Array(parts.dropFirst())

        Task {
            _ = try? await service.cliService.execute(
                command: command,
                arguments: arguments
            )
        }
    }
}
