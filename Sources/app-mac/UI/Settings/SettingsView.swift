import sdk_aws
import service_deploy
import SwiftUI

/// Settings view for configuring AWS credentials and other app settings
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // AWS settings
    @State private var profileName: String = ""
    @State private var showingAWSHelp: Bool = false

    // GitHub settings
    @State private var githubRepository: String = ""
    @State private var githubBranch: String = ""
    @State private var githubWorkflow: String = ""
    @State private var showingGitHubHelp: Bool = false

    @State private var saveError: String?
    @State private var hasChanges: Bool = false

    /// Callback when settings are saved
    var onSave: (() -> Void)?

    init(onSave: (() -> Void)? = nil) {
        self.onSave = onSave

        // Load current AWS config
        if let config = AWSAuthConfiguration.loadConfig() {
            _profileName = State(initialValue: config.profileName)
        }

        // Load current GitHub config
        if let config = GitHubConfiguration.loadConfig() {
            _githubRepository = State(initialValue: config.repository)
            _githubBranch = State(initialValue: config.branch)
            _githubWorkflow = State(initialValue: config.workflowName ?? "")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // AWS Configuration Section
                    awsConfigSection

                    Divider()

                    // GitHub Configuration Section
                    githubConfigSection

                    Divider()

                    // AWS Help Section
                    awsHelpSection
                }
                .padding()
            }

            Divider()

            // Footer with save button
            HStack {
                if let error = saveError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Spacer()
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasValidInput)
            }
            .padding()
        }
        .frame(width: 450, height: 600)
    }

    // MARK: - Validation

    private var hasValidInput: Bool {
        // At least one section should be configured
        let hasAWS = !profileName.trimmingCharacters(in: .whitespaces).isEmpty
        let hasGitHub = !githubRepository.trimmingCharacters(in: .whitespaces).isEmpty
            && !githubBranch.trimmingCharacters(in: .whitespaces).isEmpty
        return hasAWS || hasGitHub
    }

    // MARK: - AWS Configuration Section

    @ViewBuilder
    private var awsConfigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("AWS Configuration", systemImage: "cloud")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                // Profile name
                VStack(alignment: .leading, spacing: 4) {
                    Text("AWS Profile Name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("e.g., production, default", text: $profileName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: profileName) { hasChanges = true }
                }

                // aws-vault hint
                Button {
                    showingAWSHelp = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                        Text("Using aws-vault? See setup instructions")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            // Config file location
            HStack {
                Text("Config file:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(AWSAuthConfiguration.configPath)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - GitHub Configuration Section

    @ViewBuilder
    private var githubConfigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("GitHub Configuration", systemImage: "arrow.triangle.branch")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                // Repository
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repository")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("owner/repo (e.g., gestrich/swift-lambda-sample)", text: $githubRepository)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: githubRepository) { hasChanges = true }
                }

                // Branch
                VStack(alignment: .leading, spacing: 4) {
                    Text("Branch")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("e.g., dev, main", text: $githubBranch)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: githubBranch) { hasChanges = true }
                }

                // Workflow
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workflow")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("e.g., deploy_dev.yml (optional)", text: $githubWorkflow)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: githubWorkflow) { hasChanges = true }
                    Text("Filters CI status to only show this workflow")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Help hint
                Button {
                    showingGitHubHelp.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                        Text("What is this for?")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)

                if showingGitHubHelp {
                    Text("GitHub CI integration monitors your repository's GitHub Actions workflows and enables deployment triggers from the app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            // Config file location
            HStack {
                Text("Config file:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(GitHubConfiguration.configPath)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - AWS Help Section

    @ViewBuilder
    private var awsHelpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showingAWSHelp.toggle()
            } label: {
                HStack {
                    Label("AWS Setup Help", systemImage: "questionmark.circle")
                        .font(.headline)
                    Spacer()
                    Image(systemName: showingAWSHelp ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showingAWSHelp {
                helpContent
            }
        }
    }

    @ViewBuilder
    private var helpContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Traditional credentials
            VStack(alignment: .leading, spacing: 8) {
                Text("Standard AWS Credentials")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("1. Configure your AWS profile:")
                    .font(.caption)
                codeBlock("aws configure --profile your-profile-name")

                Text("2. Enter your profile name above and save")
                    .font(.caption)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)

            // aws-vault
            VStack(alignment: .leading, spacing: 8) {
                Text("Using aws-vault")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("aws-vault requires a wrapper script to work with the Mac app:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("1. Create the export script:")
                    .font(.caption)
                codeBlock("""
                    cat > ~/.swiftSampleDemo/aws-vault-export.sh << 'EOF'
                    #!/bin/bash
                    export HOME=$HOME
                    export AWS_VAULT_KEYCHAIN_NAME=login
                    exec /opt/homebrew/bin/aws-vault export --format=json your-profile
                    EOF
                    chmod +x ~/.swiftSampleDemo/aws-vault-export.sh
                    """)

                Text("2. Add a credential_process profile to ~/.aws/config:")
                    .font(.caption)
                codeBlock("""
                    [profile your-profile-vault]
                    region = us-east-1
                    credential_process = ~/.swiftSampleDemo/aws-vault-export.sh
                    """)

                Text("3. Enter 'your-profile-vault' as the profile name above")
                    .font(.caption)

                Text("4. Prime your aws-vault session before using the app:")
                    .font(.caption)
                codeBlock("aws-vault exec your-profile -- echo \"Session primed\"")
            }
            .padding()
            .background(Color.purple.opacity(0.1))
            .cornerRadius(8)

            // List available profiles
            VStack(alignment: .leading, spacing: 8) {
                Text("Find Your Profiles")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("List AWS CLI profiles:")
                    .font(.caption)
                codeBlock("aws configure list-profiles")

                Text("List aws-vault profiles:")
                    .font(.caption)
                codeBlock("aws-vault list")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func codeBlock(_ code: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
        } label: {
            HStack {
                Text(code)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(.green.opacity(0.7))
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.8))
            .foregroundColor(.green)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help("Click to copy")
    }

    // MARK: - Actions

    private func save() {
        saveError = nil

        do {
            // Save AWS config if profile is provided
            let trimmedProfile = profileName.trimmingCharacters(in: .whitespaces)
            if !trimmedProfile.isEmpty {
                let awsConfig = AWSAuthConfiguration(
                    profileName: trimmedProfile,
                    useAWSVault: false  // Mac app always uses profile mode
                )
                try awsConfig.save()
            }

            // Save GitHub config if both fields are provided
            let trimmedRepo = githubRepository.trimmingCharacters(in: .whitespaces)
            let trimmedBranch = githubBranch.trimmingCharacters(in: .whitespaces)
            let trimmedWorkflow = githubWorkflow.trimmingCharacters(in: .whitespaces)
            if !trimmedRepo.isEmpty && !trimmedBranch.isEmpty {
                let githubConfig = GitHubConfiguration(
                    repository: trimmedRepo,
                    branch: trimmedBranch,
                    workflowName: trimmedWorkflow.isEmpty ? nil : trimmedWorkflow
                )
                try githubConfig.save()
            }

            hasChanges = false
            onSave?()
            dismiss()
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
