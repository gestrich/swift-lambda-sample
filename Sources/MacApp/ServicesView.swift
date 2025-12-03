import SwiftDeploy
import SwiftUI

/// Top-level view for selecting between Remote, Xcode, and Linux service modes
/// Contains a segmented control to switch between RemoteServiceView and LocalServiceView
struct ServicesView: View {
    @Environment(MacAppModel.self) var model

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

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Service Mode Picker (Remote / Xcode / Linux)
            VStack(alignment: .leading, spacing: 8) {
                Text("Service")
                    .font(.headline)

                Picker("Service Mode", selection: modeBinding) {
                    Text("Remote").tag(RemoteService.persistenceKey)
                    Text("Xcode").tag(XcodeLocalService.persistenceKey)
                    Text("Linux").tag(LinuxLocalService.persistenceKey)
                }
                .pickerStyle(.segmented)

                Text(model.mode.detailText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(20)

            Divider()

            // MARK: - Service-Specific Content
            if model.mode.isRemote {
                RemoteServiceView(service: model.remoteService)
            } else {
                LocalServiceView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    let model = MacAppModel()
    return ServicesView()
        .environment(model)
}
