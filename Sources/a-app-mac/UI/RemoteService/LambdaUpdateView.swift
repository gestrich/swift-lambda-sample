import d_sdk_cli
import c_service_deploy_remote
import SwiftUI

/// Enum for Lambda update method selection
enum LambdaUpdateMethod: String, CaseIterable, Identifiable {
    case github = "GitHub"
    case local = "Local"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .github: return "arrow.triangle.branch"
        case .local: return "desktopcomputer"
        }
    }

    var description: String {
        switch self {
        case .github: return "Push to GitHub and deploy via CI/CD"
        case .local: return "Build locally and upload directly to AWS"
        }
    }
}

/// View for Lambda code updates with GitHub CI or direct upload options
struct LambdaUpdateView: View {
    var githubCIModel: GitHubCIModel?
    var lambdaBuildService: LambdaBuildService?
    @State private var selectedMethod: LambdaUpdateMethod = .github

    /// Callback to open settings
    var onOpenSettings: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with picker
            HStack {
                Text("Lambda Update")
                    .font(.headline)

                Spacer()

                Picker("Method", selection: $selectedMethod) {
                    ForEach(LambdaUpdateMethod.allCases) { method in
                        Label(method.rawValue, systemImage: method.icon)
                            .tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            // Content based on selected method
            switch selectedMethod {
            case .github:
                githubContent
            case .local:
                localContent
            }
        }
    }

    // MARK: - GitHub Content

    @ViewBuilder
    private var githubContent: some View {
        if let ghModel = githubCIModel {
            GitHubCISectionView(model: ghModel)
                .transition(.opacity)
        } else {
            GitHubCILoadingView(onOpenSettings: onOpenSettings)
                .transition(.opacity)
        }
    }

    // MARK: - Local Content

    @ViewBuilder
    private var localContent: some View {
        if let buildService = lambdaBuildService {
            LocalLambdaUpdateView(service: buildService)
                .transition(.opacity)
        } else {
            LambdaUploadLoadingView(onOpenSettings: onOpenSettings)
                .transition(.opacity)
        }
    }
}

// MARK: - Preview

#Preview {
    LambdaUpdateView(
        githubCIModel: nil,
        lambdaBuildService: nil
    )
    .padding()
    .frame(width: 500)
}
