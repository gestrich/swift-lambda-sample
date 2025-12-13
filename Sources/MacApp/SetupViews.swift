import SwiftUI

// MARK: - Overview View

struct OverviewView: View {
    var onNavigateToSetup: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                aboutSection
                gettingStartedSection
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
        VStack(alignment: .leading, spacing: 12) {
            Text("About This App")
                .sectionHeader()

            Text("This app demonstrates building and deploying a complete serverless application using Swift on AWS Lambda.")
                .bodyText()

            Text("It also serves as a starting point for creating your own serverless applications. There are many decisions to make when building a Swift serverless app—infrastructure, CI/CD, local development, security, and more. This project provides sensible defaults so you can get started quickly and customize from there.")
                .bodyText()

            Text("Explore development principles and deployment options using the sidebar navigation.")
                .bodyText()
        }
        .card()
    }

    private var gettingStartedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Getting Started")
                .sectionHeader()

            HStack(spacing: 0) {
                Spacer()
                WorkflowStep(icon: "book.fill", title: "Learn", color: .blue)
                WorkflowArrow()
                WorkflowStep(icon: "wrench.and.screwdriver.fill", title: "Setup", color: .orange)
                WorkflowArrow()
                WorkflowStep(icon: "arrow.up.circle.fill", title: "Deploy", color: .green)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .card()
    }
}

// MARK: - Workflow Components

private struct WorkflowStep: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(width: 80)
    }
}

private struct WorkflowArrow: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.title3)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
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

            VStack(spacing: 8) {
                AWSServiceRow(
                    name: "API Gateway",
                    description: "REST API endpoint that routes HTTP requests to Lambda",
                    icon: "arrow.left.arrow.right",
                    color: .purple
                )
                AWSServiceRow(
                    name: "Lambda",
                    description: "Serverless compute running your Swift code",
                    icon: "bolt.fill",
                    color: .orange
                )
                AWSServiceRow(
                    name: "PostgreSQL (RDS)",
                    description: "Relational database for structured data storage",
                    icon: "cylinder.fill",
                    color: .blue
                )
                AWSServiceRow(
                    name: "S3",
                    description: "Object storage for files and assets",
                    icon: "externaldrive.fill",
                    color: .green
                )
                AWSServiceRow(
                    name: "SQS",
                    description: "Message queue for async task processing",
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
    let icon: String
    let color: Color

    var body: some View {
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
        }
        .padding(12)
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
    OverviewView(onNavigateToSetup: {})
        .frame(width: 600, height: 500)
}

#Preview("Dependency") {
    DependencyView(dependency: .docker)
        .frame(width: 600, height: 600)
}
