import c_service_deploy_remote
import c_service_lambda_build
import SwiftUI

/// Placeholder when LambdaUploadService is not available (config missing)
struct LambdaUploadLoadingView: View {
    /// Callback to open settings
    var onOpenSettings: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Not Configured")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Text("Configure your AWS profile in Settings to enable local Lambda builds and uploads.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let onOpenSettings {
                    Button {
                        onOpenSettings()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape")
                            Text("Open Settings")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

/// View for local Lambda build and upload with two distinct steps
struct LocalLambdaUpdateView: View {
    @State var service: LambdaBuildService
    @State private var buildStartTime: Date?

    /// Convenience accessor for build state
    private var buildState: BuildState {
        service.buildState
    }

    /// Check if lambda.zip exists (built successfully)
    private var isBuilt: Bool {
        service.isLambdaBuilt()
    }

    /// Check if currently building
    private var isBuilding: Bool {
        buildState.status.isBuilding
    }

    /// Check if build failed
    private var hasFailed: Bool {
        if case .failed = buildState.status { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Step 1: Build
            buildSection

            // Step 2: Upload
            uploadSection
        }
        .onChange(of: isBuilding) { _, newValue in
            if newValue {
                buildStartTime = Date()
            } else {
                buildStartTime = nil
            }
        }
    }

    // MARK: - Build Section

    @ViewBuilder
    private var buildSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Step 1: Build", systemImage: "hammer")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                // Build status indicator
                buildStatusIndicator
            }

            Text("Build Lambda for linux/amd64 using Docker")
                .font(.caption)
                .foregroundColor(.secondary)

            OperationOutputSection { stream, showOutput in
                HStack {
                    Button {
                        showOutput()
                        Task {
                            try? await service.build(output: stream)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "hammer")
                            Text("Build")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBuilding || service.uploadStatus == .uploading)
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var buildStatusIndicator: some View {
        if isBuilding {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                if let startTime = buildStartTime {
                    Text("Building... \(startTime, style: .timer)")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .monospacedDigit()
                } else {
                    Text("Building...")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        } else if hasFailed {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                Text("Failed")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        } else if isBuilt {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("Ready")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        } else {
            EmptyView()
        }
    }

    // MARK: - Upload Section

    @ViewBuilder
    private var uploadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Step 2: Upload", systemImage: "arrow.up.circle")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                // Upload status indicator
                uploadStatusIndicator
            }

            Text("Deploy lambda.zip to AWS Lambda")
                .font(.caption)
                .foregroundColor(.secondary)

            OperationOutputSection { stream, showOutput in
                HStack {
                    Button {
                        showOutput()
                        Task {
                            try? await service.upload(output: stream)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle")
                            Text("Upload")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canUpload)

                    if let lastUpload = service.lastUploadTime {
                        Text("Uploaded \(lastUpload, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if !isBuilt && !isBuilding {
                Text("Build first to create lambda.zip")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private var canUpload: Bool {
        isBuilt && service.uploadStatus.canUpload && !isBuilding
    }

    @ViewBuilder
    private var uploadStatusIndicator: some View {
        switch service.uploadStatus {
        case .uploading:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Uploading...")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("Complete")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        case .failed(let reason) where service.lastUploadTime == nil && isBuilt:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                Text("Failed")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .help(reason)
        default:
            EmptyView()
        }
    }

}

// MARK: - Preview

#Preview {
    VStack {
        LambdaUploadLoadingView(onOpenSettings: {})
            .padding()
    }
    .frame(width: 400)
}
