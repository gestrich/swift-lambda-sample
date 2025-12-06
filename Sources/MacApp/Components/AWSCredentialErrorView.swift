import SwiftUI

/// View that explains how to fix AWS credential errors, particularly for aws-vault with MFA
struct AWSCredentialErrorView: View {
    let errorMessage: String
    var onDismiss: (() -> Void)?

    /// Check if this error is related to aws-vault credentials
    static func isCredentialError(_ error: String) -> Bool {
        let credentialPatterns = [
            "credentials missing",
            "credential_process",
            "Error getting temporary credentials",
            "ExpiredToken",
            "InvalidClientTokenId",
            "AccessDenied",
            "AuthFailure"
        ]
        return credentialPatterns.contains { error.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                Text("AWS Session Expired")
                    .font(.headline)
                Spacer()
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Explanation
            Text("Your aws-vault session has expired and needs to be refreshed with MFA.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            // Steps
            VStack(alignment: .leading, spacing: 12) {
                stepView(number: 1, title: "Open Terminal")

                stepView(number: 2, title: "Run this command:", code: "aws-vault exec production -- echo \"Session primed\"")

                stepView(number: 3, title: "Enter your MFA code when prompted")

                stepView(number: 4, title: "Return here and refresh")
            }

            // Copy button for the command
            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("aws-vault exec production -- echo \"Session primed\"", forType: .string)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Command")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            // Error details (collapsible)
            DisclosureGroup("Error Details") {
                Text(errorMessage)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func stepView(number: Int, title: String, code: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.orange)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)

                if let code {
                    Text(code)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .padding(6)
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AWSCredentialErrorView(
        errorMessage: "Error when retrieving credentials from custom-process: aws-vault: error: exec: Error getting temporary credentials: profile production: credentials missing"
    )
    .padding()
    .frame(width: 400)
}
