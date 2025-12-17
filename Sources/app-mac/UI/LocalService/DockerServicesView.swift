import AppKit
import service_deploy_local
import service_deploy_core
import SwiftUI

/// View for managing Docker services (MinIO S3, PostgreSQL, and DynamoDB)
/// Used in local development modes (Xcode and Linux)
struct DockerServicesView: View {
    let dockerProvider: any LocalService
    let s3State: ServiceState
    let postgresState: ServiceState
    let dynamodbState: ServiceState
    let onRefreshStatus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Docker Services")
                .font(.headline)

            // S3 (MinIO) Row
            DockerServiceRow(
                name: "S3 (MinIO)",
                state: s3State,
                dataDirectory: dockerProvider.s3DataDirectory,
                onStart: {
                    try await dockerProvider.startS3()
                    onRefreshStatus()
                },
                onStop: {
                    try await dockerProvider.stopS3()
                    onRefreshStatus()
                }
            )

            // PostgreSQL Row
            DockerServiceRow(
                name: "PostgreSQL",
                state: postgresState,
                dataDirectory: dockerProvider.postgresDataDirectory,
                onStart: {
                    try await dockerProvider.startDatabase()
                    onRefreshStatus()
                },
                onStop: {
                    try await dockerProvider.stopDatabase()
                    onRefreshStatus()
                }
            )

            // DynamoDB Row
            DockerServiceRow(
                name: "DynamoDB",
                state: dynamodbState,
                dataDirectory: dockerProvider.dynamodbDataDirectory,
                onStart: {
                    try await dockerProvider.startDynamoDB()
                    onRefreshStatus()
                },
                onStop: {
                    try await dockerProvider.stopDynamoDB()
                    onRefreshStatus()
                }
            )
        }
    }
}

// MARK: - Docker Service Row

struct DockerServiceRow: View {
    let name: String
    let state: ServiceState
    let dataDirectory: String
    let onStart: () async throws -> Void
    let onStop: () async throws -> Void

    @State private var isLoading = false

    private var stateColor: Color {
        switch state {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .stopped: return .gray
        }
    }

    private var stateText: String {
        switch state {
        case .running: return "Running"
        case .starting: return "Starting..."
        case .stopping: return "Stopping..."
        case .stopped: return "Stopped"
        }
    }

    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)

            // Service name and status
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(stateText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Data directory button
            Button(action: {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dataDirectory)
            }) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Open data directory: \(dataDirectory)")

            // Start/Stop button
            if isLoading || state.isTransitioning {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20)
            } else if state == .running {
                Button(action: {
                    Task {
                        isLoading = true
                        defer { isLoading = false }
                        try? await onStop()
                    }
                }) {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .help("Stop \(name)")
            } else {
                Button(action: {
                    Task {
                        isLoading = true
                        defer { isLoading = false }
                        try? await onStart()
                    }
                }) {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .help("Start \(name)")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
    }
}
