import CLIKit
import SwiftUI

/// Reusable scrolling text view for streaming output with auto-scroll
/// Supports both static lines and live async sequence consumption
struct StreamingTextView: View {
    /// Static lines (for backwards compatibility)
    private let staticLines: [String]?

    /// Stream iteration closure that yields lines incrementally
    private let streamConsumer: (@Sendable @escaping @MainActor (StreamOutput) -> Void) async -> Void

    let onClear: (() -> Void)?
    let isClearDisabled: Bool

    /// Live lines accumulated from the stream
    @State private var liveLines: [String] = []

    /// Maximum number of lines to display
    private let maxDisplayLines = 500

    /// Lines to display (capped at maxDisplayLines, showing most recent)
    private var displayLines: [String] {
        let lines = staticLines ?? liveLines
        if lines.count > maxDisplayLines {
            return Array(lines.suffix(maxDisplayLines))
        }
        return lines
    }

    /// Total line count (for indicator)
    private var totalLineCount: Int {
        staticLines?.count ?? liveLines.count
    }

    // MARK: - Initializers

    /// Initialize with static lines (existing behavior)
    init(lines: [String], isClearDisabled: Bool = false, onClear: (() -> Void)? = nil) {
        self.staticLines = lines
        self.streamConsumer = { _ in }
        self.isClearDisabled = isClearDisabled
        self.onClear = onClear
    }

    /// Initialize with an async sequence of StreamOutput
    init<S: AsyncSequence>(
        stream: S,
        isClearDisabled: Bool = false,
        onClear: (() -> Void)? = nil
    ) where S.Element == StreamOutput, S: Sendable, S.Failure == Never {
        self.staticLines = nil
        self.isClearDisabled = isClearDisabled
        self.onClear = onClear

        // Capture stream iteration in a closure that calls back for each output
        self.streamConsumer = { @Sendable callback in
            for await output in stream {
                await callback(output)
            }
        }
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
                .onChange(of: totalLineCount) { _, _ in
                    // Auto-scroll to bottom when new output arrives
                    if !displayLines.isEmpty {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(displayLines.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(minHeight: 150, maxHeight: 300)
            .task {
                // Only run stream consumer if we're in stream mode
                guard staticLines == nil else { return }
                await consumeStream()
            }

            // Line count indicator
            HStack {
                if totalLineCount > maxDisplayLines {
                    Text("\(maxDisplayLines) of \(totalLineCount) lines (showing latest)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(totalLineCount) lines")
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

    // MARK: - Stream Consumption

    /// Consume the async stream and append lines incrementally
    @MainActor
    private func consumeStream() async {
        await streamConsumer { output in
            processOutput(output)
        }
    }

    /// Process a StreamOutput and append to liveLines
    @MainActor
    private func processOutput(_ output: StreamOutput) {
        switch output {
        case .stdout(let text), .stderr(let text):
            appendText(text)
        case .exit, .error:
            break
        }
    }

    /// Append text to liveLines, handling line breaks
    @MainActor
    private func appendText(_ text: String) {
        // Split incoming text into lines
        let newLines = text.components(separatedBy: .newlines)
        for (index, line) in newLines.enumerated() {
            if index == 0 && !liveLines.isEmpty {
                // Append to the last line if we're continuing
                liveLines[liveLines.count - 1] += line
            } else if !line.isEmpty || index < newLines.count - 1 {
                // Add new line (skip trailing empty from \n at end)
                liveLines.append(line)
            }
        }
    }

    // MARK: - Line Coloring

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

// MARK: - Previews

#Preview("Static Lines") {
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
