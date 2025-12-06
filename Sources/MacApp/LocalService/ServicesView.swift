import SwiftDeploy
import SwiftUI

/// Top-level view for selecting between Remote, Xcode, and Linux service modes
/// Contains a segmented control to switch between RemoteServiceView and LocalServiceView
struct ServicesView: View {
    @Environment(AllServicesModel.self) var model

    private var modeBinding: Binding<String> {
        Binding(
            get: { model.mode.persistenceKey },
            set: { key in
                switch key {
                case RemoteService.persistenceKey:
                    model.setRemote()
                case XcodeLocalService.persistenceKey:
                    model.setLocalXcode()
                case LinuxLocalService.persistenceKey:
                    model.setLocalLinux()
                default:
                    break
                }
            }
        )
    }

    /// Detail text for the currently selected mode
    private var currentDetailText: String {
        switch model.mode {
        case .remote: return RemoteService.detailText
        case .localXcode: return XcodeLocalService.detailText
        case .localLinux: return LinuxLocalService.detailText
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Service Mode Picker (Remote / Xcode / Linux)
            VStack(alignment: .leading, spacing: 8) {
                Picker("Service Mode", selection: modeBinding) {
                    Text("Remote").tag(RemoteService.persistenceKey)
                    Text("Xcode").tag(XcodeLocalService.persistenceKey)
                    Text("Linux").tag(LinuxLocalService.persistenceKey)
                }
                .pickerStyle(.segmented)

                Text(currentDetailText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(20)

            Divider()
            
            HStack(spacing: 0) {
                // MARK: - Deployment Pane
                VStack(alignment: .leading, spacing: 0) {
                    Text("Deployment")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding()

                    switch model.mode {
                    case .localXcode:
                        LocalServiceView(service: model.xcodeLocalModel)
                    case .localLinux:
                        LocalServiceView(service: model.linuxLocalModel)
                    case .remote(let service):
                        RemoteServiceView(service: service)
                    }
                }

                if model.isConfigured {
                    Divider()

                    // MARK: - Client API Pane
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Client API")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding()

                        ClientView(apiClient: model.mode.service.apiClient)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    let model = AllServicesModel()
    return ServicesView()
        .environment(model)
}
