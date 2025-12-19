import SetupFeature
import SwiftUI

/// Navigation category for the main sidebar
enum AppCategory: Identifiable, Hashable {
    // Learn
    case overview
    case awsServices

    // Setup (Dependencies)
    case docker
    case awsCLI
    case cdk
    case githubCLI

    // Development Principles
    case principle(Principle)

    // Deployment
    case remote
    case xcode
    case linux

    var id: String {
        switch self {
        case .overview: return "overview"
        case .awsServices: return "awsServices"
        case .docker: return "docker"
        case .awsCLI: return "awsCLI"
        case .cdk: return "cdk"
        case .githubCLI: return "githubCLI"
        case .principle(let p): return "principle-\(p.rawValue)"
        case .remote: return "remote"
        case .xcode: return "xcode"
        case .linux: return "linux"
        }
    }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .awsServices: return "AWS Services"
        case .docker: return "Docker"
        case .awsCLI: return "AWS CLI"
        case .cdk: return "AWS CDK"
        case .githubCLI: return "GitHub CLI"
        case .principle(let p): return p.title
        case .remote: return "Remote"
        case .xcode: return "Xcode"
        case .linux: return "Linux"
        }
    }

    var iconName: String {
        switch self {
        case .overview: return "swift"
        case .awsServices: return "cloud.fill"
        case .docker: return "shippingbox.fill"
        case .awsCLI: return "terminal.fill"
        case .cdk: return "square.stack.3d.up.fill"
        case .githubCLI: return "chevron.left.forwardslash.chevron.right"
        case .principle(let p): return p.iconName
        case .remote: return "cloud.fill"
        case .xcode: return "hammer.fill"
        case .linux: return "server.rack"
        }
    }

    var iconColor: Color {
        switch self {
        case .overview: return .orange
        case .awsServices: return .orange
        case .docker: return .blue
        case .awsCLI: return .orange
        case .cdk: return .purple
        case .githubCLI: return .primary
        case .principle(let p): return p.iconColor
        case .remote: return .blue
        case .xcode: return .blue
        case .linux: return .orange
        }
    }

    var subtitle: String? {
        switch self {
        case .remote: return "Deploy to AWS"
        case .xcode: return "Fast iteration"
        case .linux: return "AWS-compatible"
        case .principle(let p): return p.subtitle
        default: return nil
        }
    }

    /// Restore category from persisted ID
    static func from(id: String) -> AppCategory? {
        switch id {
        case "overview": return .overview
        case "projectStructure": return .overview  // Legacy: redirect to overview
        case "awsServices": return .awsServices
        case "homebrew": return .docker  // Legacy: redirect to docker
        case "nodejs": return .cdk  // Legacy: redirect to cdk
        case "docker": return .docker
        case "awsCLI": return .awsCLI
        case "cdk": return .cdk
        case "githubCLI": return .githubCLI
        case "remote": return .remote
        case "xcode": return .xcode
        case "linux": return .linux
        default:
            // Check for principle IDs (format: "principle-{rawValue}")
            if id.hasPrefix("principle-") {
                let principleRawValue = String(id.dropFirst("principle-".count))
                if let principle = Principle(rawValue: principleRawValue) {
                    return .principle(principle)
                }
            }
            return nil
        }
    }
}

/// Root view for the app with sidebar navigation
struct ServicesView: View {
    @Environment(AppModel.self) var model
    @State private var selectedCategory: AppCategory?
    @State private var showingSettings = false
    @AppStorage("selectedCategoryId") private var savedCategoryId: String = AppCategory.overview.id

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            if let category = selectedCategory {
                detailView(for: category)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView {
                model.refreshStatus()
            }
        }
        .onAppear {
            restoreSelection()
        }
        .onChange(of: selectedCategory) { _, newValue in
            if let category = newValue {
                savedCategoryId = category.id
            }
        }
    }

    // MARK: - Selection Persistence

    private func restoreSelection() {
        selectedCategory = AppCategory.from(id: savedCategoryId)
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: $selectedCategory) {
            Section("Learn") {
                NavigationLink(value: AppCategory.overview) {
                    categoryRow(.overview)
                }
                NavigationLink(value: AppCategory.awsServices) {
                    categoryRow(.awsServices)
                }
                ForEach(Principle.allCases) { principle in
                    NavigationLink(value: AppCategory.principle(principle)) {
                        categoryRow(.principle(principle))
                    }
                }
            }

            Section("Setup") {
                ForEach([AppCategory.cdk, .awsCLI, .docker, .githubCLI], id: \.self) { category in
                    NavigationLink(value: category) {
                        categoryRow(category)
                    }
                }
            }

            Section("Deployment") {
                ForEach([AppCategory.remote, .xcode, .linux], id: \.self) { category in
                    NavigationLink(value: category) {
                        deploymentRow(category)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
    }

    private func categoryRow(_ category: AppCategory) -> some View {
        HStack(spacing: 10) {
            Image(systemName: category.iconName)
                .font(.body)
                .foregroundStyle(category.iconColor)
                .frame(width: 20)

            Text(category.title)
                .font(.body)

            Spacer()

            dependencyStatusIndicator(for: category)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func dependencyStatusIndicator(for category: AppCategory) -> some View {
        let tool: CLITool? = {
            switch category {
            case .docker: return .docker
            case .awsCLI: return .awsCLI
            case .cdk: return .cdk
            case .githubCLI: return .githubCLI
            default: return nil
            }
        }()

        if let tool {
            let statusModel = model.dependencyStatusModel
            let toolStatus = statusModel.status(for: tool)

            if statusModel.isChecking || statusModel.isInstalling(tool) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            } else if let toolStatus {
                if toolStatus.isInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }
        }
    }

    private func deploymentRow(_ category: AppCategory) -> some View {
        HStack(spacing: 10) {
            Image(systemName: category.iconName)
                .font(.body)
                .foregroundStyle(category.iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.body)
                if let subtitle = category.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail Views

    @ViewBuilder
    private func detailView(for category: AppCategory) -> some View {
        switch category {
        case .overview:
            OverviewView()
        case .awsServices:
            AWSServicesView()
        case .docker:
            DependencyView(dependency: .docker, statusModel: model.dependencyStatusModel)
        case .awsCLI:
            DependencyView(dependency: .awsCLI, statusModel: model.dependencyStatusModel)
        case .cdk:
            DependencyView(dependency: .cdk, statusModel: model.dependencyStatusModel)
        case .githubCLI:
            DependencyView(dependency: .githubCLI, statusModel: model.dependencyStatusModel)
        case .principle(let principle):
            switch principle {
            case .cicd:
                CICDView()
            case .localDevelopment:
                LocalDevelopmentView()
            case .productionMonitoring:
                ProductionMonitoringView()
            case .security:
                SecurityView()
            }
        case .remote:
            remoteDetailView
        case .xcode:
            xcodeDetailView
        case .linux:
            linuxDetailView
        }
    }

    // MARK: - Deployment Detail Views

    @ViewBuilder
    private var remoteDetailView: some View {
        if let remoteService = model.remoteModel {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    DeploymentExplainer(
                        icon: "cloud.fill",
                        iconColor: .blue,
                        title: "Deploy to AWS",
                        summary: "Deploy infrastructure with CDK and Lambda code via GitHub Actions",
                        details: [
                            ExplainerDetail(
                                icon: "square.stack.3d.up.fill",
                                title: "CDK Infrastructure",
                                description: "AWS CDK deploys the full infrastructure stack including VPC, API Gateway, RDS, S3, and SQS. Run deploy commands from this view to provision or update resources.",
                                color: .purple
                            ),
                            ExplainerDetail(
                                icon: "arrow.triangle.2.circlepath",
                                title: "GitHub Actions",
                                description: "Lambda code is built and deployed automatically via GitHub Actions when you push to dev or main. The build uses Docker to compile Swift for Linux.",
                                color: .blue
                            ),
                            ExplainerDetail(
                                icon: "bolt.fill",
                                title: "Lambda Updates",
                                description: "After GitHub Actions builds the Lambda, it uploads the zip directly to AWS. Infrastructure and Lambda code are deployed independently.",
                                color: .orange
                            )
                        ]
                    )
                    .padding()

                    RemoteServiceView(service: remoteService, onOpenSettings: {
                        showingSettings = true
                    })
                }

                if remoteService.state.isConfigured {
                    Divider()
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader(title: "Client API", subtitle: "Test API endpoints")
                        ClientView(apiClient: remoteService.apiClient)
                    }
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DeploymentExplainer(
                        icon: "cloud.fill",
                        iconColor: .blue,
                        title: "Deploy to AWS",
                        summary: "Deploy infrastructure with CDK and Lambda code via GitHub Actions",
                        details: [
                            ExplainerDetail(
                                icon: "square.stack.3d.up.fill",
                                title: "CDK Infrastructure",
                                description: "AWS CDK deploys the full infrastructure stack including VPC, API Gateway, RDS, S3, and SQS. Run deploy commands from this view to provision or update resources.",
                                color: .purple
                            ),
                            ExplainerDetail(
                                icon: "arrow.triangle.2.circlepath",
                                title: "GitHub Actions",
                                description: "Lambda code is built and deployed automatically via GitHub Actions when you push to dev or main. The build uses Docker to compile Swift for Linux.",
                                color: .blue
                            ),
                            ExplainerDetail(
                                icon: "bolt.fill",
                                title: "Lambda Updates",
                                description: "After GitHub Actions builds the Lambda, it uploads the zip directly to AWS. Infrastructure and Lambda code are deployed independently.",
                                color: .orange
                            )
                        ]
                    )

                    AWSCredentialErrorView(
                        errorMessage: model.remoteServiceError?.localizedDescription ?? "AWS configuration is missing"
                    )
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private var xcodeDetailView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                DeploymentExplainer(
                    icon: "hammer.fill",
                    iconColor: .blue,
                    title: "Xcode Development",
                    summary: "Build and run natively on macOS for fast iteration",
                    details: [
                        ExplainerDetail(
                            icon: "swift",
                            title: "Native Builds",
                            description: "Compiles Swift directly on macOS without Docker. Fastest build times for rapid development and debugging with full Xcode integration.",
                            color: .orange
                        ),
                        ExplainerDetail(
                            icon: "shippingbox.fill",
                            title: "Local Services",
                            description: "Uses Docker containers for PostgreSQL and MinIO (S3-compatible). Services run locally with data persisted in ~/.swiftSampleDemo/.",
                            color: .blue
                        ),
                        ExplainerDetail(
                            icon: "exclamationmark.triangle.fill",
                            title: "Platform Differences",
                            description: "Native builds run on macOS, not Linux. Some platform-specific behavior may differ. Use Linux workflow to verify compatibility before deploying.",
                            color: .orange
                        )
                    ]
                )
                .padding()

                LocalServiceView(service: model.xcodeLocalModel)
            }

            if model.xcodeLocalService.isConfigured {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(title: "Client API", subtitle: "Test API endpoints")
                    ClientView(apiClient: model.xcodeLocalService.apiClient)
                }
            }
        }
        .onAppear {
            Task {
                await model.xcodeLocalModel.startIfNecessary()
            }
        }
    }

    @ViewBuilder
    private var linuxDetailView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                DeploymentExplainer(
                    icon: "server.rack",
                    iconColor: .orange,
                    title: "Linux Container",
                    summary: "Build and run in a Docker container matching AWS Lambda",
                    details: [
                        ExplainerDetail(
                            icon: "checkmark.seal.fill",
                            title: "AWS Compatibility",
                            description: "Builds using the same Amazon Linux 2 Docker image as CI/CD. Ensures your code works correctly on the AWS Lambda runtime before deploying.",
                            color: .green
                        ),
                        ExplainerDetail(
                            icon: "shippingbox.fill",
                            title: "Docker Build",
                            description: "Uses build.sh to compile Swift for linux/amd64. Slower than native builds but guarantees Linux compatibility.",
                            color: .blue
                        ),
                        ExplainerDetail(
                            icon: "network",
                            title: "Container Networking",
                            description: "Lambda container connects to PostgreSQL and MinIO via Docker network. All services communicate as they would in a real deployment.",
                            color: .purple
                        )
                    ]
                )
                .padding()

                LocalServiceView(service: model.linuxLocalModel)
            }

            if model.linuxLocalService.isConfigured {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(title: "Client API", subtitle: "Test API endpoints")
                    ClientView(apiClient: model.linuxLocalService.apiClient)
                }
            }
        }
        .onAppear {
            Task {
                await model.linuxLocalModel.startIfNecessary()
            }
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    let model = AppModel()
    return ServicesView()
        .environment(model)
        .environment(model.githubModel)
}
