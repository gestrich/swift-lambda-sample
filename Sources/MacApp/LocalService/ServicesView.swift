import SwiftDeploy
import SwiftUI

/// Navigation category for the main sidebar
enum AppCategory: Identifiable, Hashable {
    // Getting Started
    case overview

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
    @Environment(AllServicesModel.self) var model
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
            Section("About") {
                NavigationLink(value: AppCategory.overview) {
                    categoryRow(.overview)
                }
                ForEach(Principle.allCases) { principle in
                    NavigationLink(value: AppCategory.principle(principle)) {
                        categoryRow(.principle(principle))
                    }
                }
            }

            Section("Setup") {
                ForEach([AppCategory.docker, .awsCLI, .cdk, .githubCLI], id: \.self) { category in
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
        }
        .padding(.vertical, 2)
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
            OverviewView(onNavigateToSetup: {
                selectedCategory = .docker
            })
        case .docker:
            DependencyView(dependency: .docker)
        case .awsCLI:
            DependencyView(dependency: .awsCLI)
        case .cdk:
            DependencyView(dependency: .cdk)
        case .githubCLI:
            DependencyView(dependency: .githubCLI)
        case .principle(let principle):
            PrincipleDetailView(principle: principle)
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
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(title: "Deployment", subtitle: RemoteService.detailText)
                RemoteServiceView(service: model.remoteService, onOpenSettings: {
                    showingSettings = true
                })
            }

            if model.remoteService.isConfigured {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(title: "Client API", subtitle: "Test API endpoints")
                    ClientView(apiClient: model.remoteService.apiClient)
                }
            }
        }
    }

    @ViewBuilder
    private var xcodeDetailView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(title: "Deployment", subtitle: XcodeLocalService.detailText)
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
                sectionHeader(title: "Deployment", subtitle: LinuxLocalService.detailText)
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
    let model = AllServicesModel()
    return ServicesView()
        .environment(model)
}
