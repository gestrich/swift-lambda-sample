import SwiftUI

/// Simple banner view for AWS credential errors that points users to Settings
struct AWSCredentialErrorBanner: View {
    let errorMessage: String
    var onOpenSettings: (() -> Void)?
    var onRetry: (() -> Void)?

    /// Check if this error is related to AWS credentials
    static func isCredentialError(_ error: String) -> Bool {
        let credentialPatterns = [
            "credentials missing",
            "credential_process",
            "Error getting temporary credentials",
            "ExpiredToken",
            "InvalidClientTokenId",
            "AccessDenied",
            "AuthFailure",
            "security token included in the request is invalid",
            "could not be found"  // Profile not found
        ]
        return credentialPatterns.contains { error.localizedCaseInsensitiveContains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("AWS Credentials Error")
                    .font(.headline)
            }

            // Message
            Text("Unable to connect to AWS. Check your AWS configuration in Settings.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Buttons
            HStack {
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

                if let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                // Error details disclosure
                DisclosureGroup("Details") {
                    Text(errorMessage)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    AWSCredentialErrorBanner(
        errorMessage: "The config profile (default) could not be found",
        onOpenSettings: {},
        onRetry: {}
    )
    .padding()
    .frame(width: 400)
}
