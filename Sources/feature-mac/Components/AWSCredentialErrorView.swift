import service_deploy
import SwiftUI

/// View that explains how to fix AWS credential errors based on configuration state
struct AWSCredentialErrorView: View {
    let errorMessage: String
    var onRetry: (() -> Void)?

    /// The current AWS auth configuration (nil if config file doesn't exist)
    private let awsConfig: AWSAuthConfiguration?

    /// Whether the config file exists
    private let configFileExists: Bool

    init(errorMessage: String, onRetry: (() -> Void)? = nil) {
        self.errorMessage = errorMessage
        self.onRetry = onRetry
        self.awsConfig = AWSAuthConfiguration.loadConfig()
        self.configFileExists = FileManager.default.fileExists(atPath: AWSAuthConfiguration.configPath)
    }

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

    private var configState: ConfigState {
        if !configFileExists {
            return .noConfigFile
        } else if let config = awsConfig {
            if config.useAWSVault {
                return .awsVault(profile: config.profileName)
            } else {
                return .traditionalCredentials(profile: config.profileName)
            }
        } else {
            return .invalidConfigFile
        }
    }

    private enum ConfigState {
        case noConfigFile
        case invalidConfigFile
        case traditionalCredentials(profile: String)
        case awsVault(profile: String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                Text(headerTitle)
                    .font(.headline)
                Spacer()
            }

            // Explanation
            Text(explanationText)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            // Steps based on config state
            stepsView

            // Retry button
            if let onRetry {
                HStack {
                    Spacer()
                    Button {
                        onRetry()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
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

    // MARK: - Dynamic Content

    private var headerTitle: String {
        switch configState {
        case .noConfigFile, .invalidConfigFile:
            return "AWS Not Configured"
        case .traditionalCredentials:
            return "AWS Credentials Invalid"
        case .awsVault:
            return "AWS Session Expired"
        }
    }

    private var explanationText: String {
        switch configState {
        case .noConfigFile:
            return "Create an AWS configuration file to connect to your AWS account."
        case .invalidConfigFile:
            return "The AWS configuration file exists but couldn't be read. Check the file format."
        case .traditionalCredentials(let profile):
            return "The AWS profile '\(profile)' has invalid or expired credentials."
        case .awsVault(let profile):
            return "Your aws-vault session for '\(profile)' has expired and needs to be refreshed with MFA."
        }
    }

    @ViewBuilder
    private var stepsView: some View {
        switch configState {
        case .noConfigFile:
            noConfigFileSteps
        case .invalidConfigFile:
            invalidConfigFileSteps
        case .traditionalCredentials(let profile):
            traditionalCredentialsSteps(profile: profile)
        case .awsVault(let profile):
            awsVaultSteps(profile: profile)
        }
    }

    // MARK: - Step Views

    @ViewBuilder
    private var noConfigFileSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepView(number: 1, title: "Create the config file:")

            codeBlock("""
                mkdir -p ~/.swiftSampleDemo
                cat > ~/.swiftSampleDemo/aws-config.json << 'EOF'
                {
                  "profileName": "your-profile-name",
                  "useAWSVault": false
                }
                EOF
                """)

            stepView(number: 2, title: "Set profileName to your AWS CLI profile")

            stepView(number: 3, title: "Set useAWSVault to true if using aws-vault")

            stepView(number: 4, title: "Return here and refresh")
        }
    }

    @ViewBuilder
    private var invalidConfigFileSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepView(number: 1, title: "Check the config file format:")

            codeBlock("cat ~/.swiftSampleDemo/aws-config.json")

            stepView(number: 2, title: "Ensure it contains valid JSON with profileName and useAWSVault")

            stepView(number: 3, title: "Return here and refresh")
        }
    }

    @ViewBuilder
    private func traditionalCredentialsSteps(profile: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            stepView(number: 1, title: "Check your AWS credentials:")

            codeBlock("aws sts get-caller-identity --profile \(profile)")

            stepView(number: 2, title: "If expired, refresh your credentials:")

            codeBlock("aws configure --profile \(profile)")

            stepView(number: 3, title: "Return here and refresh")
        }
    }

    @ViewBuilder
    private func awsVaultSteps(profile: String) -> some View {
        let command = "aws-vault exec \(profile) -- aws sts get-caller-identity"

        VStack(alignment: .leading, spacing: 12) {
            stepView(number: 1, title: "Open Terminal")

            stepView(number: 2, title: "Run this command:")

            codeBlock(command)

            stepView(number: 3, title: "Enter your MFA code when prompted")

            stepView(number: 4, title: "Return here and refresh")

            // Copy button
            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Command")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func stepView(number: Int, title: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.orange)
                .clipShape(Circle())

            Text(title)
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(.caption)
            .fontDesign(.monospaced)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.8))
            .foregroundColor(.green)
            .cornerRadius(4)
            .textSelection(.enabled)
            .padding(.leading, 30)
    }
}

// MARK: - Preview

#Preview("No Config File") {
    AWSCredentialErrorView(
        errorMessage: "The config profile (default) could not be found"
    )
    .padding()
    .frame(width: 450)
}

#Preview("AWS Vault Expired") {
    AWSCredentialErrorView(
        errorMessage: "Error getting temporary credentials: profile production: credentials missing"
    )
    .padding()
    .frame(width: 450)
}
