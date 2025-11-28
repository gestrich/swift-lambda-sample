import SwiftUI
import SwiftDeploy

/// View displaying streaming build output with auto-scroll
struct BuildOutputView: View {
    let buildState: BuildState

    /// Maximum number of lines to display
    private let maxDisplayLines = 500

    /// Lines to display (capped at maxDisplayLines, showing most recent)
    private var displayLines: [String] {
        if buildState.outputLines.count > maxDisplayLines {
            return Array(buildState.outputLines.suffix(maxDisplayLines))
        }
        return buildState.outputLines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with status
            HStack {
                Text("Build Output")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                statusBadge
            }

            // Output area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(lineColor(for: line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: buildState.outputLines.count) { _, _ in
                    // Auto-scroll to bottom when new output arrives
                    if !displayLines.isEmpty {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(displayLines.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(minHeight: 150, maxHeight: 300)

            // Line count indicator
            HStack {
                if buildState.outputLines.count > maxDisplayLines {
                    Text("\(displayLines.count) of \(buildState.outputLines.count) lines (showing latest)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(displayLines.count) lines")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !displayLines.isEmpty && !buildState.status.isBuilding {
                    Button("Clear") {
                        buildState.clear()
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch buildState.status {
        case .idle:
            EmptyView()
        case .building:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Building...")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Success")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Failed")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }

    /// Determine line color based on content
    private func lineColor(for line: String) -> Color {
        if line.contains("error:") || line.contains("Error:") || line.contains("❌") {
            return .red
        } else if line.contains("warning:") {
            return .orange
        } else if line.contains("✅") || line.contains("Build completed") {
            return .green
        } else if line.contains("🔨") || line.contains("🧹") {
            return .blue
        }
        return .primary
    }
}

#Preview {
    BuildOutputView(buildState: BuildState())
        .padding()
        .frame(width: 500)
}
