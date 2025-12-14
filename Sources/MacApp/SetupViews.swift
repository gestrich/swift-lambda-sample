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
            return "AWS CDK (Cloud Development Kit) is used to define and deploy the infrastructure as TypeScript code. Requires Node.js and npm."
        case .githubCLI:
            return "The GitHub CLI (gh) is used for monitoring GitHub Actions deployment workflows."
        }
    }

    var installCommand: any CLICommand {
        switch self {
        case .docker:
            return Brew.Install(cask: true, package: "docker")
        case .awsCLI:
            return Brew.Install(package: "awscli")
        case .cdk:
            return Npm.Install(global: true, package: "aws-cdk")
        case .githubCLI:
            return Brew.Install(package: "gh")
        }
    }

    var verifyCommand: any CLICommand {
        switch self {
        case .docker:
            return Docker.Version()
        case .awsCLI:
            return Aws.Version()
        case .cdk:
            return Cdk.Version()
        case .githubCLI:
            return Gh.Version()
        }
    }

    var uninstallCommand: any CLICommand {
        switch self {
        case .docker:
            return Brew.Uninstall(cask: true, package: "docker")
        case .awsCLI:
            return Brew.Uninstall(package: "awscli")
        case .cdk:
            return Npm.Uninstall(global: true, package: "aws-cdk")
        case .githubCLI:
            return Brew.Uninstall(package: "gh")
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

    @State private var showCommandsSheet = false

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
                documentationSection
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showCommandsSheet) {
            DependencyCommandsSheet(dependency: dependency, cliService: cliService, statusService: statusService)
        }
    }

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: dependency.iconName)
                .font(.system(size: 40))
                .foregroundStyle(dependency.iconColor)
                .onLongPressGesture {
                    showCommandsSheet = true
                }
                .help("Long press for developer commands")

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

    private var documentationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installation")
                .sectionHeader()

            Text("Follow the official documentation to install this dependency:")
                .bodyText()

            Link(destination: URL(string: dependency.documentationURL)!) {
                HStack(spacing: 8) {
                    Image(systemName: "book.fill")
                    Text("View Installation Guide")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.body)
                .padding(12)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .card()
    }
}

// MARK: - Dependency Commands Sheet (Secret Developer View)

private struct DependencyCommandsSheet: View {
    let dependency: Dependency
    let cliService: CLIService
    let statusService: DependencyStatusService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Developer Commands")
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
                VStack(alignment: .leading, spacing: 20) {
                    Text("These commands assume Homebrew (brew) and npm are installed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    // Install
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Install")
                            .font(.headline)
                        RunnableCommandView(command: dependency.installCommand, cliService: cliService, onComplete: refreshStatus)
                    }

                    // Verify
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Verify Installation")
                            .font(.headline)
                        RunnableCommandView(command: dependency.verifyCommand, cliService: cliService, onComplete: refreshStatus)
                    }

                    // Uninstall
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Uninstall")
                            .font(.headline)
                        RunnableCommandView(command: dependency.uninstallCommand, cliService: cliService, onComplete: refreshStatus)
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 450)
    }

    private func refreshStatus() async {
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
}

// MARK: - Runnable Command View

/// A command block that can be run with streaming output display
struct RunnableCommandView: View {
    let command: any CLICommand
    let cliService: CLIService
    var onComplete: (() async -> Void)? = nil

    @State private var isRunning = false
    @State private var outputText = ""
    @State private var exitCode: Int32?

    private var commandString: String {
        command.commandString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Command display with buttons
            HStack(spacing: 0) {
                // Run button on the left
                Button {
                    Task {
                        await runCommand()
                    }
                } label: {
                    Group {
                        if isRunning {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
                .help("Run command")

                // Command text
                Text(commandString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.2))

                // Copy button on the right
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(commandString, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
                .padding(.trailing, 12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Output section (shown when running or has output)
            if isRunning || !outputText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if isRunning {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 14, height: 14)
                        } else if let code = exitCode {
                            Image(systemName: code == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(code == 0 ? .green : .red)
                        }
                        Text(isRunning ? "Running..." : "Output")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !isRunning && !outputText.isEmpty {
                            Button("Clear") {
                                outputText = ""
                                exitCode = nil
                            }
                            .font(.caption2)
                            .buttonStyle(.borderless)
                        }
                    }

                    ScrollView {
                        Text(outputText.isEmpty ? " " : outputText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 150)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.leading, 12)
            }
        }
    }

    private func runCommand() async {
        isRunning = true
        outputText = ""
        exitCode = nil

        // Use stream() for real-time output with typed command
        let stream = await cliService.stream(command)

        for await output in stream {
            switch output {
            case .command(_, let text):
                outputText += text
            case .stdout(_, let text):
                outputText += text
            case .stderr(_, let text):
                outputText += text
            case .exit(_, let code):
                exitCode = code
            case .error(_, let error):
                outputText += "Error: \(error.localizedDescription)\n"
                exitCode = 1
            }
        }

        isRunning = false

        if let onComplete {
            await onComplete()
        }
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
