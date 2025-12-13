import SwiftUI

// MARK: - Principle Enum (for sidebar navigation)

enum Principle: String, CaseIterable, Identifiable {
    case cicd
    case localDevelopment
    case productionMonitoring
    case security

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cicd: return "CI / CD"
        case .localDevelopment: return "Local Development"
        case .productionMonitoring: return "Production Monitoring"
        case .security: return "Security"
        }
    }

    var subtitle: String {
        switch self {
        case .cicd: return "Automated builds and deployments"
        case .localDevelopment: return "Development environment setup"
        case .productionMonitoring: return "Logs, alerts, and performance"
        case .security: return "Secrets and credential management"
        }
    }

    var iconName: String {
        switch self {
        case .cicd: return "arrow.triangle.2.circlepath"
        case .localDevelopment: return "laptopcomputer"
        case .productionMonitoring: return "chart.line.uptrend.xyaxis"
        case .security: return "lock.shield.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .cicd: return .blue
        case .localDevelopment: return .green
        case .productionMonitoring: return .orange
        case .security: return .purple
        }
    }
}

// MARK: - CI/CD View

struct CICDView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                overviewSection
                workflowsSection
                buildSection
                deploymentSection
            }
            .padding(32)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("CI / CD")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Automated builds and deployments")
                    .bodyText()
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .sectionHeader()

            Text("This project uses GitHub Actions for continuous integration and deployment. When code is pushed to the dev or main branch, it automatically builds the Swift Lambda and deploys it to AWS.")
                .bodyText()
        }
        .card()
    }

    private var workflowsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub Actions Workflows")
                .sectionHeader()

            Text("Workflow files in .github/workflows/ define the CI/CD pipeline.")
                .bodyText()

            VStack(spacing: 8) {
                ExpandableRow(
                    icon: "play.circle.fill",
                    title: "deploy_dev.yml",
                    description: "Triggers on pushes to dev branch",
                    details: "The main development workflow. Triggers on pushes to the dev branch and manual dispatch. Calls the reusable deploy.yml workflow with the dev environment configuration. Tests are currently disabled for faster iteration.",
                    color: .blue
                )
                ExpandableRow(
                    icon: "checkmark.seal.fill",
                    title: "deploy_prod.yml",
                    description: "Triggers on pushes to main branch",
                    details: "Production deployment workflow. Triggers on pushes to main and manual dispatch. Runs tests before deployment and only deploys if tests pass. Uses a different Lambda function name for production isolation.",
                    color: .green
                )
                ExpandableRow(
                    icon: "arrow.triangle.2.circlepath.circle.fill",
                    title: "deploy.yml",
                    description: "Reusable deployment workflow",
                    details: "Parameterized workflow that handles the actual build and deployment. Accepts environment, Lambda name, and platform parameters. Configures AWS credentials via OIDC, runs build.sh for Docker-based compilation, and updates Lambda code via AWS CLI.",
                    color: .orange
                )
                ExpandableRow(
                    icon: "testtube.2",
                    title: "test.yml",
                    description: "Runs Swift unit tests",
                    details: "Executes swift test with Swift 5.9. Requires GitHub netrc configuration for private package dependencies. Runs on pushes to feature branches (not dev or main).",
                    color: .purple
                )
            }
        }
        .card()
    }

    private var buildSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Build Process")
                .sectionHeader()

            Text("The build process compiles Swift for AWS Lambda's Linux environment using Docker.")
                .bodyText()

            VStack(spacing: 8) {
                ExpandableRow(
                    icon: "hammer.fill",
                    title: "build.sh",
                    description: "Docker-based Lambda compilation script",
                    details: "Cross-compiles Swift for linux/amd64 using the swift:6.0-amazonlinux2 Docker image. Resolves Swift packages, builds in release mode, strips debug symbols, and packages the binary with runtime dependencies into lambda.zip. Validates the package is under AWS Lambda's 50MB limit.",
                    color: .orange
                )
                ExpandableRow(
                    icon: "shippingbox.fill",
                    title: "Docker Environment",
                    description: "Amazon Linux 2 with Swift 6.0",
                    details: "Uses the official Swift Amazon Linux 2 image to match AWS Lambda's runtime environment. Installs build dependencies (git, openssl, sqlite, curl) and mounts GitHub credentials for private package access.",
                    color: .blue
                )
                ExpandableRow(
                    icon: "doc.zipper",
                    title: "lambda.zip",
                    description: "Deployment package artifact",
                    details: "The final deployment package containing the Swift binary (named 'bootstrap' for Lambda), all Swift runtime libraries, and shared library dependencies. Automatically collected from the Docker build and uploaded as a GitHub Actions artifact.",
                    color: .green
                )
            }
        }
        .card()
    }

    private var deploymentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Deployment")
                .sectionHeader()

            Text("Lambda code is deployed directly via AWS CLI after a successful build.")
                .bodyText()

            VStack(spacing: 8) {
                ExpandableRow(
                    icon: "key.fill",
                    title: "OIDC Authentication",
                    description: "Secure, keyless AWS access",
                    details: "Uses OpenID Connect (OIDC) to assume an AWS IAM role without storing credentials. GitHub Actions exchanges a short-lived token for temporary AWS credentials. The role ARN is stored as a repository secret.",
                    color: .purple
                )
                ExpandableRow(
                    icon: "arrow.up.circle.fill",
                    title: "Lambda Update",
                    description: "aws lambda update-function-code",
                    details: "After building, the workflow uploads lambda.zip directly to AWS Lambda using the AWS CLI. The function code is updated in place without changing configuration. Deployment typically completes in 2-3 minutes from push.",
                    color: .green
                )
                ExpandableRow(
                    icon: "square.stack.3d.up.fill",
                    title: "Infrastructure (CDK)",
                    description: "Managed separately via AWS CDK",
                    details: "Infrastructure changes (VPC, RDS, API Gateway, etc.) are deployed separately using the SwiftDeploy CLI tool. CDK deployment is not part of the automated CI/CD pipeline to prevent accidental infrastructure changes.",
                    color: .cyan
                )
            }
        }
        .card()
    }
}

// MARK: - Local Development View

struct LocalDevelopmentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                overviewSection
                workflowsSection
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
            Image(systemName: "laptopcomputer")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("Local Development")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Development environment setup")
                    .bodyText()
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .sectionHeader()

            Text("Local development uses Docker containers to run AWS-compatible services on your Mac. This allows you to develop and test without deploying to AWS.")
                .bodyText()
        }
        .card()
    }

    private var workflowsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Development Workflows")
                .sectionHeader()

            Text("Two workflows are available depending on your needs.")
                .bodyText()

            VStack(spacing: 8) {
                ExpandableRow(
                    icon: "hammer.fill",
                    title: "Xcode Workflow",
                    description: "Fast iteration with native builds",
                    details: "Builds and runs the Lambda natively on macOS for the fastest development cycle. Great for rapid iteration and debugging. Uses local Docker services for PostgreSQL and S3 (MinIO). Start with 'swift run SwiftDeploy local xcode start-all'.",
                    color: .blue
                )
                ExpandableRow(
                    icon: "server.rack",
                    title: "Linux Workflow",
                    description: "AWS-compatible container testing",
                    details: "Builds and runs the Lambda in a Docker container matching the AWS environment. Use this to verify Linux compatibility before deploying. Start with 'swift run SwiftDeploy local linux start-all'.",
                    color: .orange
                )
            }
        }
        .card()
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Services")
                .sectionHeader()

            Text("Docker containers provide local versions of AWS services.")
                .bodyText()

            VStack(spacing: 8) {
                ExpandableRow(
                    icon: "cylinder.fill",
                    title: "PostgreSQL",
                    description: "Local database container",
                    details: "Runs PostgreSQL in Docker with persistent data storage in ~/.swiftSampleDemo/postgres/. Accessible on localhost:5432. Credentials are configured in the local environment.",
                    color: .blue
                )
                ExpandableRow(
                    icon: "externaldrive.fill",
                    title: "MinIO (S3)",
                    description: "S3-compatible object storage",
                    details: "MinIO provides an S3-compatible API for local file storage testing. Runs on localhost:9000 with a web console on localhost:9001. Data persists in ~/.swiftSampleDemo/minio/.",
                    color: .green
                )
            }
        }
        .card()
    }
}

// MARK: - Production Monitoring View

struct ProductionMonitoringView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                overviewSection
                loggingSection
                alertingSection
            }
            .padding(32)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Production Monitoring")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Logs, alerts, and performance")
                    .bodyText()
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .sectionHeader()

            Text("AWS CloudWatch provides logging and monitoring for the Lambda function. Logs are automatically captured and can be viewed via the AWS Console or CLI.")
                .bodyText()
        }
        .card()
    }

    private var loggingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Logging")
                .sectionHeader()

            Text("Lambda execution logs are sent to CloudWatch Logs.")
                .bodyText()

            VStack(spacing: 8) {
                ExpandableRow(
                    icon: "doc.text.fill",
                    title: "CloudWatch Logs",
                    description: "Centralized log storage",
                    details: "All Lambda output (print statements, errors, Swift logging) is captured in CloudWatch Logs under /aws/lambda/swift-lambda-sample. Logs are retained according to your CloudWatch retention policy.",
                    color: .blue
                )
                ExpandableRow(
                    icon: "terminal.fill",
                    title: "CLI Log Access",
                    description: "View logs via SwiftDeploy",
                    details: "Use 'swift run SwiftDeploy aws logs' to tail recent logs. Supports --since flag for time-based filtering (e.g., --since 1h). Also available via 'aws logs tail' directly.",
                    color: .green
                )
            }
        }
        .card()
    }

    private var alertingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Alerting & Performance")
                .sectionHeader()

            Text("CloudWatch can be configured for alerts and performance monitoring.")
                .bodyText()

            VStack(spacing: 8) {
                ExpandableRow(
                    icon: "bell.fill",
                    title: "CloudWatch Alarms",
                    description: "Error and threshold alerts",
                    details: "CloudWatch Alarms can notify you of Lambda errors, high latency, or throttling. Configure alarms in the AWS Console or via CDK. Notifications can be sent to email, Slack, or PagerDuty via SNS.",
                    color: .orange
                )
                ExpandableRow(
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    title: "Performance Metrics",
                    description: "Invocation duration and memory",
                    details: "CloudWatch automatically tracks Lambda invocation count, duration, errors, and memory usage. View metrics in the AWS Console under Lambda > Monitor, or create custom dashboards.",
                    color: .purple
                )
            }
        }
        .card()
    }
}

// MARK: - Security View

struct SecurityView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                overviewSection
                secretsSection
                authSection
            }
            .padding(32)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 4) {
                Text("Security")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Secrets and credential management")
                    .bodyText()
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .sectionHeader()

            Text("Security best practices are followed to protect credentials and sensitive data. No secrets are stored in the repository, and all credentials are managed through AWS services.")
                .bodyText()
        }
        .card()
    }

    private var secretsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Secrets Management")
                .sectionHeader()

            Text("Sensitive values are stored securely and accessed at runtime.")
                .bodyText()

            VStack(spacing: 8) {
                ExpandableRow(
                    icon: "key.fill",
                    title: "AWS Secrets Manager",
                    description: "Database credentials storage",
                    details: "Database passwords are stored in AWS Secrets Manager and retrieved by the Lambda at runtime. The CDK automatically creates and manages the secret. Credentials are never logged or exposed in environment variables.",
                    color: .purple
                )
                ExpandableRow(
                    icon: "lock.rectangle.fill",
                    title: "GitHub Secrets",
                    description: "CI/CD credentials",
                    details: "The AWS role ARN and Swift package manager token are stored as GitHub repository secrets. These are injected into GitHub Actions workflows but never exposed in logs. OIDC is used instead of long-lived access keys.",
                    color: .blue
                )
                ExpandableRow(
                    icon: "externaldrive.badge.person.crop",
                    title: "Local Credentials",
                    description: "Developer machine security",
                    details: "Local AWS credentials can be stored in ~/.aws/credentials or managed via aws-vault for enhanced security. aws-vault stores credentials in your system keychain rather than plaintext files.",
                    color: .green
                )
            }
        }
        .card()
    }

    private var authSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Authentication")
                .sectionHeader()

            Text("Secure authentication patterns for CI/CD and runtime.")
                .bodyText()

            VStack(spacing: 8) {
                ExpandableRow(
                    icon: "person.badge.key.fill",
                    title: "OIDC for CI/CD",
                    description: "Keyless AWS authentication",
                    details: "GitHub Actions uses OpenID Connect to authenticate with AWS without storing access keys. A short-lived token is exchanged for temporary AWS credentials that expire after the workflow completes.",
                    color: .orange
                )
                ExpandableRow(
                    icon: "checkmark.shield.fill",
                    title: "IAM Least Privilege",
                    description: "Minimal required permissions",
                    details: "The Lambda execution role has only the permissions needed to access specific resources (RDS, S3, SQS, Secrets Manager). Permissions are defined in CDK and can be audited in the AWS Console.",
                    color: .cyan
                )
            }
        }
        .card()
    }
}

// MARK: - Previews

#Preview("CI/CD") {
    CICDView()
        .frame(width: 600, height: 800)
}

#Preview("Local Development") {
    LocalDevelopmentView()
        .frame(width: 600, height: 700)
}

#Preview("Production Monitoring") {
    ProductionMonitoringView()
        .frame(width: 600, height: 700)
}

#Preview("Security") {
    SecurityView()
        .frame(width: 600, height: 700)
}
