import SwiftDeploy
import SwiftUI

/// Unified view for displaying streaming CLI output with status badge.
/// Works with any state conforming to `CLIOutputState` (BuildState, LambdaState, etc.)
struct CLIOutputView<State: CLIOutputState>: View {
    let title: String
    let state: State

    @SwiftUI.State private var isExpanded = false

    /// Whether there's content to show
    private var hasOutput: Bool {
        !state.outputLines.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with status and expand toggle
            HStack {
                // Expand/collapse button (only when there's output)
                if hasOutput {
                    Button(action: { withAnimation { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                }

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                statusBadge
            }

            // Output area (collapsible)
            if isExpanded && hasOutput {
                StreamingTextView(
                    lines: state.outputLines,
                    isClearDisabled: state.status.isActive
                ) {
                    state.clear()
                    isExpanded = false
                }
            }
        }
        .onChange(of: state.status.isActive) { _, isActive in
            // Auto-expand when status becomes active
            if isActive {
                withAnimation {
                    isExpanded = true
                }
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            if state.status.showProgress {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Image(systemName: state.status.iconName)
                    .foregroundColor(statusColor)
            }
            Text(state.status.displayText)
                .font(.caption2)
                .foregroundColor(statusColor)
        }
        .help(state.status.helpText ?? "")
    }

    private var statusColor: Color {
        switch state.status.colorName {
        case "blue":
            return .blue
        case "green":
            return .green
        case "orange":
            return .orange
        case "red":
            return .red
        case "secondary":
            return .secondary
        default:
            return .primary
        }
    }
}

// MARK: - Convenience Type Aliases

/// Convenience type for build output view
typealias BuildOutputView = CLIOutputView<BuildState>

/// Convenience type for lambda output view
typealias LambdaOutputView = CLIOutputView<LambdaState>

// MARK: - Convenience Initializers

extension CLIOutputView where State == BuildState {
    /// Convenience initializer for build output
    init(buildState: BuildState) {
        self.init(title: "Build Output", state: buildState)
    }
}

extension CLIOutputView where State == LambdaState {
    /// Convenience initializer for lambda output
    init(lambdaState: LambdaState) {
        self.init(title: "Lambda Output", state: lambdaState)
    }
}

// MARK: - Previews

#Preview("Build Output") {
    CLIOutputView(title: "Build Output", state: BuildState())
        .padding()
        .frame(width: 500)
}

#Preview("Lambda Output") {
    CLIOutputView(title: "Lambda Output", state: LambdaState())
        .padding()
        .frame(width: 500)
}
