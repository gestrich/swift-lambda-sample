import SwiftUI

// MARK: - Overview View

struct OverviewView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                aboutSection
            }
            .padding(32)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                AWSServiceRow(
                    name: "API Gateway",
                    description: "REST API endpoint that routes HTTP requests to Lambda",
                    details: "Provides a public HTTPS endpoint for the application. Routes incoming requests to the Lambda function based on path and HTTP method. Handles request/response transformation and provides built-in throttling and monitoring.",
                    icon: "arrow.left.arrow.right",
                    color: .purple
                )
                AWSServiceRow(
                    name: "Lambda",
                    description: "Serverless compute running your Swift code",
                    details: "Executes the Swift application code in response to API Gateway requests. Scales automatically based on demand. Configured with VPC access to reach RDS and other private resources. Includes environment variables for service configuration.",
                    icon: "bolt.fill",
                    color: .orange
                )
                AWSServiceRow(
                    name: "RDS",
                    description: "PostgreSQL relational database for structured data",
                    details: "Managed PostgreSQL instance running in a private subnet. Stores user data and application state. Connected via SSL/TLS with credentials managed in Secrets Manager. The Lambda function uses the Swift PostgresNIO driver to interact with the database.",
                    icon: "cylinder.fill",
                    color: .blue
                )
                AWSServiceRow(
                    name: "S3",
                    description: "Object storage for files and assets",
                    details: "Stores uploaded files and binary assets. The Lambda function uses the AWS SDK for Swift to upload and download objects. Bucket is configured with appropriate IAM permissions for Lambda access.",
                    icon: "externaldrive.fill",
                    color: .green
                )
                AWSServiceRow(
                    name: "SQS",
                    description: "Message queue for async task processing",
                    details: "Enables asynchronous processing of tasks. Messages can be sent from the Lambda function for background processing. Includes a Dead Letter Queue for failed message handling.",
                    icon: "tray.full.fill",
                    color: .pink
                )
            }
        }
        .card()
    }
}

// MARK: - AWS Service Row

private struct AWSServiceRow: View {
    let name: String
    let description: String
    let details: String
    let icon: String
    let color: Color

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .subheader()
                        Text(description)
                            .bodyText()
                    }
                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(details)
                    .bodyText()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .padding(.leading, 40)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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

    var installCommand: String {
        switch self {
        case .docker:
            return "brew install --cask docker"
        case .awsCLI:
            return "brew install awscli"
        case .cdk:
            return "npm install -g aws-cdk"
        case .githubCLI:
            return "brew install gh"
        }
    }

    var verifyCommand: String {
        switch self {
        case .docker:
            return "docker --version"
        case .awsCLI:
            return "aws --version"
        case .cdk:
            return "cdk --version"
        case .githubCLI:
            return "gh --version"
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
            return "https://cli.github.com/manual/installation"
        }
    }
}

// MARK: - Dependency View

struct DependencyView: View {
    let dependency: Dependency

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                descriptionSection
                installSection
                verifySection
            }
            .padding(32)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: dependency.iconName)
                .font(.system(size: 40))
                .foregroundStyle(dependency.iconColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(dependency.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Required dependency")
                    .bodyText()
            }
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

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installation")
                .sectionHeader()

            CodeBlock(code: dependency.installCommand)

            Link(destination: URL(string: dependency.documentationURL)!) {
                HStack(spacing: 4) {
                    Text("View documentation")
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline)
            }
        }
        .card()
    }

    private var verifySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verify Installation")
                .sectionHeader()

            Text("Run this command to verify the installation:")
                .bodyText()

            CodeBlock(code: dependency.verifyCommand)
        }
        .card()
    }
}

// MARK: - Code Block

private struct CodeBlock: View {
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

// MARK: - Previews

#Preview("Overview") {
    OverviewView()
        .frame(width: 600, height: 500)
}

#Preview("Dependency") {
    DependencyView(dependency: .docker)
        .frame(width: 600, height: 600)
}
