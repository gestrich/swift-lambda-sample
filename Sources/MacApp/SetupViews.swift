import CLIKit
import SwiftDeploy
import SwiftUI

// MARK: - Overview View

struct OverviewView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                aboutSection
                targetsSection
                cdkSection
                dependenciesSection
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: "swift")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Swift Lambda Sample")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Building serverless applications with Swift on AWS")
                    .bodyText()
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About This App")
                .sectionHeader()

            Text("This app demonstrates building and deploying a complete serverless application using Swift on AWS Lambda. It also serves as a starting point for creating your own serverless applications.")
                .bodyText()

            VStack(spacing: 8) {
                WorkflowRow(
                    icon: "book.fill",
                    title: "Learn",
                    description: "Understand the AWS services and development principles used in this project",
                    color: .blue
                )
                WorkflowRow(
                    icon: "wrench.and.screwdriver.fill",
                    title: "Setup",
                    description: "Install required dependencies like Docker, AWS CLI, and CDK",
                    color: .orange
                )
                WorkflowRow(
                    icon: "arrow.up.circle.fill",
                    title: "Deploy",
                    description: "Deploy to AWS, run locally with Xcode, or test in a Linux container",
                    color: .green
                )
            }
        }
        .card()
    }

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Swift Package Targets")
                .sectionHeader()

            VStack(spacing: 0) {
                CompactExpandableRow(
                    icon: "bolt.fill",
                    title: "SwiftLambda",
                    subtitle: "Lambda executable",
                    details: "The main entry point for AWS Lambda. Handles API Gateway events and routes requests to SwiftServerApp. Built for Linux and deployed as a zip package.",
                    color: .orange
                )
                CompactExpandableRow(
                    icon: "gearshape.2.fill",
                    title: "SwiftServerApp",
                    subtitle: "Business logic",
                    details: "Contains all the application logic including database models, S3 operations, and API handlers. Depends on Fluent for PostgreSQL and Soto for AWS services.",
                    color: .blue
                )
                CompactExpandableRow(
                    icon: "macwindow",
                    title: "MacApp",
                    subtitle: "This app",
                    details: "The SwiftUI app you're using now. Provides a GUI for deploying infrastructure, running local services, and testing API endpoints.",
                    color: .purple
                )
                CompactExpandableRow(
                    icon: "terminal.fill",
                    title: "SwiftDeployCLI",
                    subtitle: "CLI tool",
                    details: "CLI alternative to the Mac app. Run with 'swift run SwiftDeployCLI' or use the tools.sh wrapper. Uses ArgumentParser for command handling.",
                    color: .green
                )
                CompactExpandableRow(
                    icon: "shippingbox.fill",
                    title: "SwiftDeploy",
                    subtitle: "Deployment library",
                    details: "Core deployment logic shared by MacApp and SwiftDeployCLI. Handles CDK deployment, GitHub Actions integration, and Docker service management.",
                    color: .cyan
                )
                CompactExpandableRow(
                    icon: "network",
                    title: "Client",
                    subtitle: "Shared models",
                    details: "Data models and API client code shared between SwiftLambda, MacApp, and SwiftDeploy. Defines the User model and API request/response types.",
                    color: .pink,
                    isLast: true
                )
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .card()
    }

    private var cdkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CDK Infrastructure")
                .sectionHeader()

            Text("TypeScript infrastructure-as-code in the cdk/ folder.")
                .bodyText()

            VStack(spacing: 0) {
                CompactExpandableRow(
                    icon: "square.stack.3d.up.fill",
                    title: "swift-lambda-stack.ts",
                    subtitle: "Main stack",
                    details: "Composes all infrastructure constructs together. Orchestrates VPC, Lambda, API Gateway, databases, and other services. Exports CloudFormation outputs.",
                    color: .purple
                )
                CompactExpandableRow(
                    icon: "network",
                    title: "vpc-construct.ts",
                    subtitle: "Networking",
                    details: "Creates the Virtual Private Cloud with public and private subnets across multiple availability zones. Configures NAT Gateway for Lambda outbound access.",
                    color: .green
                )
                CompactExpandableRow(
                    icon: "bolt.fill",
                    title: "lambda-construct.ts",
                    subtitle: "Compute",
                    details: "Defines the Swift Lambda function configuration. Sets memory, timeout, VPC placement, environment variables, and IAM permissions.",
                    color: .yellow
                )
                CompactExpandableRow(
                    icon: "arrow.left.arrow.right",
                    title: "api-gateway-construct.ts",
                    subtitle: "HTTP endpoint",
                    details: "Creates the public HTTP endpoint. Configures routes, CORS, and Lambda integration. Outputs the API URL used to invoke the Lambda.",
                    color: .pink
                )
                CompactExpandableRow(
                    icon: "cylinder.fill",
                    title: "database-construct.ts",
                    subtitle: "PostgreSQL",
                    details: "Provisions the PostgreSQL database in a private subnet. Manages security groups, credentials in Secrets Manager, and connection parameters.",
                    color: .blue
                )
                CompactExpandableRow(
                    icon: "externaldrive.fill",
                    title: "storage-construct.ts",
                    subtitle: "S3 bucket",
                    details: "Creates the S3 bucket for file storage. Configures bucket policies and grants Lambda the necessary permissions to read and write objects.",
                    color: .green
                )
                CompactExpandableRow(
                    icon: "tray.full.fill",
                    title: "queue-construct.ts",
                    subtitle: "SQS queues",
                    details: "Sets up SQS main queue and Dead Letter Queue. Configures message retention, visibility timeout, and DLQ redrive policy.",
                    color: .orange,
                    isLast: true
                )
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .card()
    }

    private var dependenciesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Swift Dependencies")
                .sectionHeader()

            VStack(spacing: 0) {
                CompactExpandableRow(
                    icon: "cloud.fill",
                    title: "Soto",
                    subtitle: "AWS SDK",
                    details: "Community-maintained AWS SDK providing SotoS3, SotoSecretsManager, and SotoDynamoDB. Used by SwiftServerApp to interact with AWS services.",
                    color: .orange
                )
                CompactExpandableRow(
                    icon: "bolt.circle.fill",
                    title: "Swift AWS Lambda Runtime",
                    subtitle: "Lambda lifecycle",
                    details: "Official Swift server library for running code on AWS Lambda. Handles the Lambda lifecycle, event parsing, and response formatting.",
                    color: .yellow
                )
                CompactExpandableRow(
                    icon: "cylinder.fill",
                    title: "Fluent + PostgresDriver",
                    subtitle: "Database ORM",
                    details: "Vapor's ORM for database operations. FluentPostgresDriver connects to RDS PostgreSQL in production.",
                    color: .blue
                )
                CompactExpandableRow(
                    icon: "terminal.fill",
                    title: "Swift Argument Parser",
                    subtitle: "CLI parsing",
                    details: "Apple's library for building command-line interfaces. Used by SwiftDeployCLI to parse commands like 'aws deploy' and 'local start-all'.",
                    color: .green,
                    isLast: true
                )
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .card()
    }
}

// MARK: - Compact Expandable Row

private struct CompactExpandableRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let details: String
    let color: Color
    var isLast: Bool = false

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(color)
                        .frame(width: 28, height: 28)
                        .background(color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(.body, weight: .medium))
                            .foregroundStyle(.primary)

                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .padding(.leading, 40)
            }

            if !isLast {
                Divider()
                    .padding(.leading, 52)
            }
        }
    }
}

// MARK: - Workflow Row

private struct WorkflowRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .subheader()
                Text(description)
                    .bodyText()
            }
            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - AWS Services View

struct AWSServicesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                servicesSection
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("AWS Services")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Cloud services used in this application")
                    .bodyText()
            }
        }
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Services")
                .sectionHeader()

            Text("These AWS cloud services are deployed via CDK infrastructure-as-code. The Swift Lambda function interacts with each of these services at runtime.")
                .bodyText()

            VStack(spacing: 8) {
                ExpandableRow(
                    icon: "arrow.left.arrow.right",
                    title: "API Gateway",
                    description: "REST API endpoint that routes HTTP requests to Lambda",
                    details: "Provides a public HTTPS endpoint for the application. Routes incoming requests to the Lambda function based on path and HTTP method. Handles request/response transformation and provides built-in throttling and monitoring.",
                    color: .purple
                )
                ExpandableRow(
                    icon: "tablecells.fill",
                    title: "DynamoDB",
                    description: "NoSQL database for flexible data storage",
                    details: "Fully managed NoSQL database with single-digit millisecond latency. Useful for high-throughput workloads and flexible schema requirements. The Lambda function uses the AWS SDK for Swift to read and write items.",
                    color: .orange
                )
                ExpandableRow(
                    icon: "bolt.fill",
                    title: "Lambda",
                    description: "Serverless compute running your Swift code",
                    details: "Executes the Swift application code in response to API Gateway requests. Scales automatically based on demand. Configured with VPC access to reach RDS and other private resources. Includes environment variables for service configuration.",
                    color: .yellow
                )
                ExpandableRow(
                    icon: "cylinder.fill",
                    title: "RDS",
                    description: "PostgreSQL relational database for structured data",
                    details: "Managed PostgreSQL instance running in a private subnet. Stores user data and application state. Connected via SSL/TLS with credentials managed in Secrets Manager. The Lambda function uses the Swift PostgresNIO driver to interact with the database.",
                    color: .blue
                )
                ExpandableRow(
                    icon: "externaldrive.fill",
                    title: "S3",
                    description: "Object storage for files and assets",
                    details: "Stores uploaded files and binary assets. The Lambda function uses the AWS SDK for Swift to upload and download objects. Bucket is configured with appropriate IAM permissions for Lambda access.",
                    color: .green
                )
                ExpandableRow(
                    icon: "tray.full.fill",
                    title: "SQS",
                    description: "Message queue for async task processing",
                    details: "Enables asynchronous processing of tasks. Messages can be sent from the Lambda function for background processing. Includes a Dead Letter Queue for failed message handling.",
                    color: .pink
                )
            }
        }
        .card()
    }
}

// MARK: - Installation Method

struct InstallationMethod: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let commandString: String?
    let downloadURL: String?
    let note: String?

    static func homebrew(_ command: String) -> InstallationMethod {
        InstallationMethod(name: "Homebrew", icon: "mug.fill", commandString: command, downloadURL: nil, note: nil)
    }

    static func npm(_ command: String, note: String? = nil) -> InstallationMethod {
        InstallationMethod(name: "npm", icon: "shippingbox.fill", commandString: command, downloadURL: nil, note: note)
    }

    static func download(_ name: String, url: String, note: String? = nil) -> InstallationMethod {
        InstallationMethod(name: name, icon: "arrow.down.circle.fill", commandString: nil, downloadURL: url, note: note)
    }
}

// MARK: - Dependency Model

enum Dependency {
    case docker
    case awsCLI
    case cdk
    case githubCLI

    var title: String {
        switch self {
        case .docker: return "Docker"
        case .awsCLI: return "AWS CLI"
        case .cdk: return "AWS CDK"
        case .githubCLI: return "GitHub CLI"
        }
    }

    var iconName: String {
        switch self {
        case .docker: return "shippingbox.fill"
        case .awsCLI: return "terminal.fill"
        case .cdk: return "square.stack.3d.up.fill"
        case .githubCLI: return "chevron.left.forwardslash.chevron.right"
        }
    }

    var iconColor: Color {
        switch self {
        case .docker: return .blue
        case .awsCLI: return .orange
        case .cdk: return .purple
        case .githubCLI: return .primary
        }
    }

    var description: String {
        switch self {
        case .docker:
            return "Docker is required to run local development services (PostgreSQL, MinIO) and to build the Lambda for Linux deployment."
        case .awsCLI:
            return "The AWS CLI is used for deploying Lambda code and interacting with AWS services."
        case .cdk:
            return "AWS CDK (Cloud Development Kit) is used to define and deploy the infrastructure as TypeScript code."
        case .githubCLI:
            return "The GitHub CLI (gh) is used for monitoring GitHub Actions deployment workflows."
        }
    }

    var installationMethods: [InstallationMethod] {
        switch self {
        case .docker:
            return [
                .download("Docker Desktop", url: "https://docs.docker.com/desktop/install/mac-install/", note: "Recommended for macOS"),
                .homebrew("brew install --cask docker")
            ]
        case .awsCLI:
            return [
                .homebrew("brew install awscli"),
                .download("macOS PKG Installer", url: "https://awscli.amazonaws.com/AWSCLIV2.pkg", note: "Official AWS installer")
            ]
        case .cdk:
            return [
                .npm("npm install -g aws-cdk", note: "Requires Node.js. Install via: brew install node"),
            ]
        case .githubCLI:
            return [
                .homebrew("brew install gh"),
                .download("Binary Releases", url: "https://github.com/cli/cli/releases", note: "Download from GitHub")
            ]
        }
    }

    var verifyCommand: String {
        switch self {
        case .docker: return "docker --version"
        case .awsCLI: return "aws --version"
        case .cdk: return "cdk --version"
        case .githubCLI: return "gh --version"
        }
    }

    var uninstallMethods: [InstallationMethod] {
        switch self {
        case .docker:
            return [
                .homebrew("brew uninstall --cask docker"),
                InstallationMethod(name: "Manual", icon: "trash", commandString: nil, downloadURL: nil, note: "Delete Docker.app from Applications")
            ]
        case .awsCLI:
            return [
                .homebrew("brew uninstall awscli"),
                InstallationMethod(name: "Manual (PKG install)", icon: "trash", commandString: "sudo rm -rf /usr/local/aws-cli && sudo rm /usr/local/bin/aws", downloadURL: nil, note: "For PKG-installed AWS CLI")
            ]
        case .cdk:
            return [
                .npm("npm uninstall -g aws-cdk", note: nil)
            ]
        case .githubCLI:
            return [
                .homebrew("brew uninstall gh")
            ]
        }
    }

    var documentationURL: String {
        switch self {
        case .docker:
            return "https://docs.docker.com/desktop/install/mac-install/"
        case .awsCLI:
            return "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        case .cdk:
            return "https://docs.aws.amazon.com/cdk/latest/guide/getting_started.html"
        case .githubCLI:
            return "https://github.com/cli/cli#installation"
        }
    }
}

// MARK: - Dependency View

struct DependencyView: View {
    let dependency: Dependency
    let statusService: DependencyStatusService

    @State private var showUninstallSheet = false

    private var cliService: CLIService {
        statusService.cliService
    }

    private var status: DependencyInstallStatus {
        switch dependency {
        case .docker: return statusService.dockerStatus
        case .awsCLI: return statusService.awsCLIStatus
        case .cdk: return statusService.cdkStatus
        case .githubCLI: return statusService.githubCLIStatus
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                statusSection
                descriptionSection
                installationSection
                verifySection
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showUninstallSheet) {
            UninstallSheet(dependency: dependency)
        }
    }

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: dependency.iconName)
                .font(.system(size: 40))
                .foregroundStyle(dependency.iconColor)
                .onLongPressGesture {
                    showUninstallSheet = true
                }
                .help("Long press for uninstall options")

            VStack(alignment: .leading, spacing: 4) {
                Text(dependency.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Required dependency")
                    .bodyText()
            }
        }
    }

    private var statusSection: some View {
        HStack(spacing: 12) {
            statusIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.headline)
                    .foregroundStyle(statusColor)

                if case .installed(let version) = status, let version {
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                Task {
                    await checkStatus()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(status.isChecking)
            .help("Check again")
        }
        .padding(16)
        .background(statusBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .unknown, .checking:
            ProgressView()
                .scaleEffect(0.8)
                .frame(width: 24, height: 24)
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
        case .notInstalled:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
        }
    }

    private var statusTitle: String {
        switch status {
        case .unknown, .checking:
            return "Checking..."
        case .installed:
            return "Installed"
        case .notInstalled:
            return "Not Installed"
        }
    }

    private var statusColor: Color {
        switch status {
        case .unknown, .checking:
            return .secondary
        case .installed:
            return .green
        case .notInstalled:
            return .orange
        }
    }

    private var statusBackgroundColor: Color {
        switch status {
        case .unknown, .checking:
            return Color(nsColor: .windowBackgroundColor)
        case .installed:
            return Color.green.opacity(0.1)
        case .notInstalled:
            return Color.orange.opacity(0.1)
        }
    }

    private func checkStatus() async {
        switch dependency {
        case .docker:
            await statusService.checkDocker()
        case .awsCLI:
            await statusService.checkAWSCLI()
        case .cdk:
            await statusService.checkCDK()
        case .githubCLI:
            await statusService.checkGitHubCLI()
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .sectionHeader()

            Text(dependency.description)
                .bodyText()
        }
        .card()
    }

    private var installationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installation Options")
                .sectionHeader()

            ForEach(dependency.installationMethods) { method in
                InstallationMethodRow(method: method)
            }

            Link(destination: URL(string: dependency.documentationURL)!) {
                HStack(spacing: 8) {
                    Image(systemName: "book.fill")
                    Text("View Official Documentation")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .card()
    }

    private var verifySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verify Installation")
                .sectionHeader()

            Text("Run this command in Terminal to verify:")
                .bodyText()

            CopyableCodeBlock(code: dependency.verifyCommand)
        }
        .card()
    }
}

// MARK: - Installation Method Row

private struct InstallationMethodRow: View {
    let method: InstallationMethod

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: method.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text(method.name)
                    .font(.headline)

                if let note = method.note {
                    Text("— \(note)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let command = method.commandString {
                CopyableCodeBlock(code: command)
            }

            if let url = method.downloadURL {
                Link(destination: URL(string: url)!) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download")
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Copyable Code Block

struct CopyableCodeBlock: View {
    let code: String

    var body: some View {
        HStack {
            Text(code)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy to clipboard")
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Uninstall Sheet

private struct UninstallSheet: View {
    let dependency: Dependency
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                Text("Uninstall \(dependency.title)")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose the uninstall method that matches how you installed \(dependency.title):")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    ForEach(dependency.uninstallMethods) { method in
                        UninstallMethodRow(method: method)
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 300)
    }
}

private struct UninstallMethodRow: View {
    let method: InstallationMethod

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: method.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text(method.name)
                    .font(.headline)

                if let note = method.note {
                    Text("— \(note)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let command = method.commandString {
                CopyableCodeBlock(code: command)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Previews

#Preview("Overview") {
    OverviewView()
        .frame(width: 600, height: 500)
}

#Preview("Dependency") {
    let model = AllServicesModel()
    return DependencyView(
        dependency: .docker,
        statusService: model.dependencyStatusService
    )
    .frame(width: 600, height: 600)
}
