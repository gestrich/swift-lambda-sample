import SwiftUI

// MARK: - Principle Enum

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

    var items: [PrincipleItem] {
        switch self {
        case .cicd:
            return [
                PrincipleItem(
                    title: "Published Documentation",
                    status: .notImplemented,
                    details: "Explore GitHub actions for the Open API Generator and DocC. Publish as GitHub pages."
                ),
                PrincipleItem(
                    title: "Automatic Builds",
                    status: .implemented,
                    details: "Using GitHub Actions"
                ),
                PrincipleItem(
                    title: "Automatic Tests",
                    status: .implemented,
                    details: "Using GitHub Actions"
                ),
                PrincipleItem(
                    title: "Automatic Deploys",
                    status: .implemented,
                    details: "Using GitHub Actions"
                ),
                PrincipleItem(
                    title: "Dev Staging Environment",
                    status: .notImplemented,
                    details: "Explore terraform workspaces"
                ),
                PrincipleItem(
                    title: "CI/CD Failure Alerts",
                    status: .notImplemented,
                    details: "Explore GitHub email/Slack alerting"
                ),
                PrincipleItem(
                    title: "Dependency Version Reporting",
                    status: .notImplemented,
                    details: "Explore GitHub Dependabot"
                ),
            ]

        case .localDevelopment:
            return [
                PrincipleItem(
                    title: "Local Dev Environment",
                    status: .partial,
                    details: "Local Docker containers to run local services (S3, DynamoDB, Postgres, etc.)."
                ),
                PrincipleItem(
                    title: "Trigger Remote APIs Locally",
                    status: .partial,
                    details: "Lambdas can be triggered from the AWS CLI with proper permissions. API GW can be hit as REST endpoints."
                ),
                PrincipleItem(
                    title: "Select Local Dependencies",
                    status: .implemented,
                    details: "Use local Swift Package dependencies by providing a local package path in Package.swift."
                ),
                PrincipleItem(
                    title: "Unit Tests Have No Environment Restrictions",
                    status: .implemented,
                    details: "Dependency injection is used to hide AWS services from testable code."
                ),
                PrincipleItem(
                    title: "Dev Environment Documentation",
                    status: .partial,
                    details: "This README has most relevant documentation but it needs improvement."
                ),
                PrincipleItem(
                    title: "Option to Build Product Locally",
                    status: .notImplemented,
                    details: "Need instructions for how to build the Docker image locally and how to log in to the Docker container for troubleshooting."
                ),
            ]

        case .productionMonitoring:
            return [
                PrincipleItem(
                    title: "Remote Logs",
                    status: .partial,
                    details: "CloudWatch is used for logging. The search capabilities are not ideal though."
                ),
                PrincipleItem(
                    title: "Failure Alerts",
                    status: .notImplemented,
                    details: "Use CloudWatch Alarms. Need to show the error in the alert somehow. Also, need to support crash logs."
                ),
                PrincipleItem(
                    title: "Remote Performance",
                    status: .notImplemented,
                    details: "Look into CloudWatch."
                ),
            ]

        case .security:
            return [
                PrincipleItem(
                    title: "No secrets in the repository",
                    status: .implemented,
                    details: "AWS Secrets Manager is used to store any required secrets."
                ),
                PrincipleItem(
                    title: "No plain-text secrets in server logs",
                    status: .partial,
                    details: "This needs to be audited. Look at the security of environment variables and what is in build logs."
                ),
            ]
        }
    }
}

// MARK: - Principle Item

struct PrincipleItem: Identifiable {
    let id = UUID()
    let title: String
    let status: PrincipleStatus
    let details: String
}

enum PrincipleStatus {
    case implemented
    case partial
    case notImplemented

    var iconName: String {
        switch self {
        case .implemented: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.triangle.fill"
        case .notImplemented: return "circle"
        }
    }

    var color: Color {
        switch self {
        case .implemented: return .green
        case .partial: return .orange
        case .notImplemented: return .secondary
        }
    }

    var label: String {
        switch self {
        case .implemented: return "Implemented"
        case .partial: return "Partial"
        case .notImplemented: return "Not Implemented"
        }
    }
}

// MARK: - Principle Detail View

struct PrincipleDetailView: View {
    let principle: Principle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                statusSummary
                itemsList
            }
            .padding(32)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: principle.iconName)
                .font(.system(size: 40))
                .foregroundStyle(principle.iconColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(principle.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(principle.subtitle)
                    .bodyText()
            }
        }
    }

    // MARK: - Status Summary

    private var statusSummary: some View {
        let implemented = principle.items.filter { $0.status == .implemented }.count
        let partial = principle.items.filter { $0.status == .partial }.count
        let notImplemented = principle.items.filter { $0.status == .notImplemented }.count

        return HStack(spacing: 24) {
            StatusCount(count: implemented, status: .implemented)
            StatusCount(count: partial, status: .partial)
            StatusCount(count: notImplemented, status: .notImplemented)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Items List

    private var itemsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Principles")
                .sectionHeader()

            ForEach(principle.items) { item in
                PrincipleItemRow(item: item)
            }
        }
    }
}

// MARK: - Status Count

private struct StatusCount: View {
    let count: Int
    let status: PrincipleStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.iconName)
                .foregroundStyle(status.color)
            Text("\(count)")
                .font(.title3)
                .fontWeight(.semibold)
            Text(status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Principle Item Row

private struct PrincipleItemRow: View {
    let item: PrincipleItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.status.iconName)
                .font(.title3)
                .foregroundStyle(item.status.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)

                Text(item.details)
                    .bodyText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Preview

#Preview("CI/CD") {
    PrincipleDetailView(principle: .cicd)
        .frame(width: 600, height: 700)
}

#Preview("Security") {
    PrincipleDetailView(principle: .security)
        .frame(width: 600, height: 500)
}
