import sdk_cli
import SwiftUI

// MARK: - Command Block Model

/// A command and its associated output, grouped together
private struct CommandBlock: Identifiable {
    let id: CommandID
    var commandText: String
    var outputLines: [String] = []
    var isComplete: Bool = false

    /// Current partial line being accumulated (not yet terminated by newline)
    var partialLine: String = ""
}

// MARK: - Streaming Text View

/// Reusable scrolling text view for streaming output with auto-scroll
/// Supports both static lines and live async sequence consumption
/// Groups output by command with collapsible sections
struct StreamingTextView: View {
    /// Static lines (for backwards compatibility)
    private let staticLines: [String]?

    /// Stream iteration closure that yields lines incrementally
    private let streamConsumer: (@Sendable @escaping @MainActor (StreamOutput) -> Void) async -> Void

    let onClear: (() -> Void)?
    let isClearDisabled: Bool

    /// Maximum lines to show per command when collapsed (nil = no limit)
    let collapsedLineLimit: Int?

    /// Command blocks accumulated from the stream
    @State private var commandBlocks: [CommandBlock] = []

    /// Set of command IDs that have been expanded by the user
    @State private var expandedCommandIDs: Set<CommandID> = []

    /// Set of command IDs we've seen (to filter orphaned output)
    @State private var knownCommandIDs: Set<CommandID> = []

    /// Maximum number of total lines to display across all commands
    private let maxDisplayLines = 500

    /// Total line count (for indicator)
    private var totalLineCount: Int {
        if let staticLines {
            return staticLines.count
        }
        return commandBlocks.reduce(0) { $0 + 1 + $1.outputLines.count } // +1 for command itself
    }

    // MARK: - Initializers

    /// Initialize with static lines (existing behavior)
    init(
        lines: [String],
        collapsedLineLimit: Int? = 5,
        isClearDisabled: Bool = false,
        onClear: (() -> Void)? = nil
    ) {
        self.staticLines = lines
        self.streamConsumer = { _ in }
        self.collapsedLineLimit = collapsedLineLimit
        self.isClearDisabled = isClearDisabled
        self.onClear = onClear
    }

    /// Initialize with an async sequence of StreamOutput
    init<S: AsyncSequence>(
        stream: S,
        collapsedLineLimit: Int? = 5,
        isClearDisabled: Bool = false,
        onClear: (() -> Void)? = nil
    ) where S.Element == StreamOutput, S: Sendable, S.Failure == Never {
        self.staticLines = nil
        self.collapsedLineLimit = collapsedLineLimit
        self.isClearDisabled = isClearDisabled
        self.onClear = onClear

        // Capture stream iteration in a closure that calls back for each output
        self.streamConsumer = { @Sendable callback in
            for await output in stream {
                await callback(output)
            }
        }
    }

    /// Initialize with an async stream provider (for when getting the stream is async)
    init(
        streamProvider: @escaping @Sendable () async -> AsyncStream<StreamOutput>,
        collapsedLineLimit: Int? = 5,
        isClearDisabled: Bool = false,
        onClear: (() -> Void)? = nil
    ) {
        self.staticLines = nil
        self.collapsedLineLimit = collapsedLineLimit
        self.isClearDisabled = isClearDisabled
        self.onClear = onClear

        self.streamConsumer = { @Sendable callback in
            let stream = await streamProvider()
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
                        if let staticLines {
                            // Static mode - just show lines
                            ForEach(Array(staticLines.enumerated()), id: \.offset) { index, line in
                                lineView(line)
                                    .id(index)
                            }
                        } else {
                            // Stream mode - show command blocks
                            ForEach(commandBlocks) { block in
                                commandBlockView(block)
                            }
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
                    if let lastBlock = commandBlocks.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(lastBlock.id, anchor: .bottom)
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
                Text("\(totalLineCount) lines")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                if onClear != nil || staticLines == nil {
                    Button("Clear") {
                        // Clear internal state for stream mode
                        if staticLines == nil {
                            commandBlocks = []
                            expandedCommandIDs = []
                            knownCommandIDs = []
                        }
                        // Also call external callback if provided
                        onClear?()
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                    .disabled(isClearDisabled)
                }
            }
        }
    }

    // MARK: - View Components

    /// Colors for command block accent bars - visually distinct, works well on dark backgrounds
    private static let blockColors: [Color] = [
        Color(red: 0.4, green: 0.7, blue: 0.9),   // Light blue
        Color(red: 0.6, green: 0.8, blue: 0.5),   // Soft green
        Color(red: 0.9, green: 0.7, blue: 0.4),   // Warm orange
        Color(red: 0.8, green: 0.5, blue: 0.7),   // Muted pink
        Color(red: 0.5, green: 0.7, blue: 0.8),   // Teal
        Color(red: 0.7, green: 0.6, blue: 0.9),   // Soft purple
    ]

    /// Get a consistent color for a command block based on its position
    private func blockColor(for index: Int) -> Color {
        Self.blockColors[index % Self.blockColors.count]
    }

    /// Extract the program name from a command string
    /// e.g. "→ /usr/local/bin/docker run ..." -> "docker"
    /// e.g. "→ AWS_PROFILE='production' /usr/local/bin/aws ..." -> "aws"
    private func programName(from commandText: String) -> String {
        // Remove the arrow prefix if present
        var text = commandText
        if text.hasPrefix("→ ") {
            text = String(text.dropFirst(2))
        }

        // Split into components and find the first one that's not an env var (KEY=VALUE)
        let components = text.components(separatedBy: " ")
        for component in components {
            // Skip empty components
            guard !component.isEmpty else { continue }

            // Skip environment variables (contain = but don't start with /)
            if component.contains("=") && !component.hasPrefix("/") {
                continue
            }

            // This should be the executable - extract just the program name
            return (component as NSString).lastPathComponent
        }

        // Fallback to first component
        return (components.first ?? text) as String
    }

    @ViewBuilder
    private func commandBlockView(_ block: CommandBlock) -> some View {
        let blockIndex = commandBlocks.firstIndex(where: { $0.id == block.id }) ?? 0
        let accentColor = blockColor(for: blockIndex)
        let isExpanded = expandedCommandIDs.contains(block.id)
        let linesToShow = outputLinesToShow(for: block, expanded: isExpanded)
        let program = programName(from: block.commandText)

        HStack(alignment: .top, spacing: 0) {
            // Colored accent bar on the left
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                // Program name header with spinner
                HStack {
                    Text(program)
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundColor(accentColor)

                    Spacer()

                    if !block.isComplete {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 2)

                // Full command line
                Text(block.commandText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)

                // Output lines (collapsed or expanded)
                ForEach(Array(linesToShow.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.85))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }

                // Show expand/collapse toggle if output exceeds limit
                if let limit = collapsedLineLimit,
                   block.outputLines.count > limit {
                    let hiddenCount = block.outputLines.count - limit
                    Button {
                        if isExpanded {
                            expandedCommandIDs.remove(block.id)
                        } else {
                            expandedCommandIDs.insert(block.id)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                            Text(isExpanded ? "Show less" : "\(hiddenCount) more")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
        .background(accentColor.opacity(0.08))
        .cornerRadius(4)
        .padding(.vertical, 2)
        .id(block.id)
    }

    private func outputLinesToShow(for block: CommandBlock, expanded: Bool) -> [String] {
        guard let limit = collapsedLineLimit, !expanded else {
            return block.outputLines
        }
        return Array(block.outputLines.prefix(limit))
    }

    private func lineView(_ line: String) -> some View {
        Text(line)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(lineColor(for: line))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Stream Consumption

    /// Consume the async stream and append lines incrementally
    @MainActor
    private func consumeStream() async {
        await streamConsumer { output in
            processOutput(output)
        }
    }

    /// Process a StreamOutput and update command blocks
    /// Filters out output from commands that started before we subscribed
    @MainActor
    private func processOutput(_ output: StreamOutput) {
        switch output {
        case .command(let id, let text):
            // New command - create a new block
            knownCommandIDs.insert(id)
            let commandText = text.trimmingCharacters(in: .newlines)
            let block = CommandBlock(id: id, commandText: commandText)
            commandBlocks.append(block)

        case .stdout(let commandID, let text), .stderr(let commandID, let text):
            // Only show output if we've seen the command that triggered it
            guard knownCommandIDs.contains(commandID) else {
                return
            }
            appendOutput(text, to: commandID)

        case .exit(let commandID, _):
            // Mark command as complete, finalize any partial line
            if let index = commandBlocks.firstIndex(where: { $0.id == commandID }) {
                if !commandBlocks[index].partialLine.isEmpty {
                    commandBlocks[index].outputLines.append(commandBlocks[index].partialLine)
                    commandBlocks[index].partialLine = ""
                }
                commandBlocks[index].isComplete = true
            }
            knownCommandIDs.remove(commandID)

        case .error(let commandID, let error):
            // Display error message and mark command as complete
            if let index = commandBlocks.firstIndex(where: { $0.id == commandID }) {
                commandBlocks[index].outputLines.append("❌ Error: \(error.localizedDescription)")
                commandBlocks[index].isComplete = true
            }
            knownCommandIDs.remove(commandID)
        }
    }

    /// Append output text to the specified command block
    @MainActor
    private func appendOutput(_ text: String, to commandID: CommandID) {
        guard let index = commandBlocks.firstIndex(where: { $0.id == commandID }) else {
            return
        }

        // Split text by newlines
        let parts = text.components(separatedBy: .newlines)

        for (partIndex, part) in parts.enumerated() {
            if partIndex == 0 {
                // First part continues the partial line
                commandBlocks[index].partialLine += part
            } else {
                // Each subsequent part means we crossed a newline
                // Commit the current partial line and start a new one
                commandBlocks[index].outputLines.append(commandBlocks[index].partialLine)
                commandBlocks[index].partialLine = part
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

#Preview("Collapsed Output") {
    // Simulate what collapsed output would look like
    VStack(alignment: .leading, spacing: 0) {
        Text("→ /usr/bin/swift build")
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.blue)
        Text("Building for debugging...")
            .font(.system(.caption, design: .monospaced))
        Text("Compiling module A")
            .font(.system(.caption, design: .monospaced))
        Text("Compiling module B")
            .font(.system(.caption, design: .monospaced))
        Text("Compiling module C")
            .font(.system(.caption, design: .monospaced))
        Text("Compiling module D")
            .font(.system(.caption, design: .monospaced))
        Button("▼ Show 45 more lines...") {}
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.accentColor)
            .buttonStyle(.plain)
            .padding(.leading, 8)
    }
    .padding()
    .background(Color(nsColor: .textBackgroundColor))
    .frame(width: 500)
}
