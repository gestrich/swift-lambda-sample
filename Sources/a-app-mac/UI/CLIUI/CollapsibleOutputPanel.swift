import d_sdk_cli
import SwiftUI

/// A collapsible output panel with Xcode-style toggle button.
/// Contains streaming output view and command input.
struct CollapsibleOutputPanel: View {
    let streamProvider: @Sendable () async -> AsyncStream<StreamOutput>
    let streamId: String
    let onCommand: (String) -> Void

    @State private var isExpanded = false
    @State private var commandText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toggle bar
            toggleBar

            // Content is always in hierarchy to preserve state, just hidden when collapsed
            Divider()
                .opacity(isExpanded ? 1 : 0)
                .frame(height: isExpanded ? nil : 0)

            VStack(alignment: .leading, spacing: 8) {
                outputSection
                commandInputSection
            }
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
            .frame(height: isExpanded ? nil : 0)
            .clipped()
            .opacity(isExpanded ? 1 : 0)
        }
    }

    // MARK: - Toggle Bar

    private var toggleBar: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(.secondary)
                Text("Output")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }

    // MARK: - Output Section

    private var outputSection: some View {
        StreamingTextView(streamProvider: streamProvider)
            .id(streamId)
    }

    // MARK: - Command Input Section

    private var commandInputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            CommandInputView(text: $commandText) { command in
                onCommand(command)
            }

            Text("Type a command and press Enter. Tab to autocomplete, arrows to navigate.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
