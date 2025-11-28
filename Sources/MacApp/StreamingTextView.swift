import SwiftUI

/// Reusable scrolling text view for streaming output with auto-scroll
struct StreamingTextView: View {
    let lines: [String]
    let onClear: (() -> Void)?
    let isClearDisabled: Bool

    /// Maximum number of lines to display
    private let maxDisplayLines = 500

    /// Lines to display (capped at maxDisplayLines, showing most recent)
    private var displayLines: [String] {
        if lines.count > maxDisplayLines {
            return Array(lines.suffix(maxDisplayLines))
        }
        return lines
    }

    init(lines: [String], isClearDisabled: Bool = false, onClear: (() -> Void)? = nil) {
        self.lines = lines
        self.isClearDisabled = isClearDisabled
        self.onClear = onClear
    }

    var body: some View {
        VStack(spacing: 4) {
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
                .onChange(of: lines.count) { _, _ in
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
                if lines.count > maxDisplayLines {
                    Text("\(maxDisplayLines) of \(lines.count) lines (showing latest)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(lines.count) lines")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let onClear = onClear {
                    Button("Clear", action: onClear)
                        .font(.caption2)
                        .buttonStyle(.borderless)
                        .disabled(isClearDisabled)
                }
            }
        }
    }

    /// Determine line color based on content
    private func lineColor(for line: String) -> Color {
        if line.contains("error:") || line.contains("Error:") || line.contains("❌") {
            return .red
        } else if line.contains("warning:") || line.contains("⚠️") {
            return .orange
        } else if line.contains("✅") || line.contains("Success") || line.contains("completed") {
            return .green
        } else if line.contains("🔨") || line.contains("🧹") || line.contains("🚀") || line.contains("🛑") || line.contains("→") {
            return .blue
        } else if line.contains("ℹ️") {
            return .cyan
        }
        return .primary
    }
}

#Preview {
    StreamingTextView(lines: [
        "🔨 Building Lambda...",
        "Compiling module A",
        "Compiling module B",
        "warning: deprecated API",
        "✅ Build completed successfully"
    ])
    .padding()
    .frame(width: 500)
}
