import SwiftDeploy
import SwiftUI

/// View displaying streaming Lambda lifecycle output with auto-scroll
struct LambdaOutputView: View {
    let lambdaState: LambdaState

    @State private var isExpanded = false

    /// Whether there's content to show
    private var hasOutput: Bool {
        !lambdaState.outputLines.isEmpty
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

                Text("Lambda Output")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                statusBadge
            }

            // Output area (collapsible)
            if isExpanded && hasOutput {
                StreamingTextView(
                    lines: lambdaState.outputLines,
                    isClearDisabled: lambdaState.status.isTransitioning
                ) {
                    lambdaState.clear()
                    isExpanded = false
                }
            }
        }
        .onChange(of: lambdaState.status.isTransitioning) { _, isTransitioning in
            // Auto-expand when Lambda is starting or stopping
            if isTransitioning {
                withAnimation {
                    isExpanded = true
                }
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch lambdaState.status {
        case .stopped:
            HStack(spacing: 4) {
                Image(systemName: "stop.circle")
                    .foregroundColor(.secondary)
                Text("Stopped")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        case .starting:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Starting...")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        case .running:
            HStack(spacing: 4) {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.green)
                Text("Running")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        case .stopping:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Stopping...")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        case .failed(let reason):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Failed")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
            .help(reason)
        }
    }
}

#Preview {
    LambdaOutputView(lambdaState: LambdaState())
        .padding()
        .frame(width: 500)
}
