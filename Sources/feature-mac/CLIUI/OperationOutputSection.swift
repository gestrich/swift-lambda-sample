import sdk_cli
import SwiftUI

/// A reusable component for displaying operation output with action buttons.
/// The view owns a persistent CLIOutputStream that accumulates output across operations.
/// Output view is hidden until an action explicitly shows it.
///
/// Usage:
/// ```swift
/// OperationOutputSection { stream, showOutput in
///     Button("Deploy") {
///         showOutput()
///         Task { try? await service.deploy(output: stream) }
///     }
///     Button("Destroy") {
///         showOutput()
///         Task { try? await service.destroy(output: stream) }
///     }
/// }
/// ```
struct OperationOutputSection<Actions: View>: View {
    /// Persistent output stream owned by this view - accumulates across operations
    @State private var output = CLIOutputStream()

    /// Track whether output section is visible
    @State private var isExpanded = false

    /// Builder for action buttons that receive the output stream and show callback
    let actions: (CLIOutputStream, @escaping () -> Void) -> Actions

    init(@ViewBuilder actions: @escaping (CLIOutputStream, @escaping () -> Void) -> Actions) {
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            actions(output) { isExpanded = true }

            // Always render StreamingTextView so it subscribes immediately,
            // but hide it visually until expanded
            StreamingTextView(
                streamProvider: { [output] in await output.makeStream() }
            )
            .frame(height: isExpanded ? nil : 0)
            .clipped()
            .opacity(isExpanded ? 1 : 0)
        }
    }
}

// MARK: - Preview

#Preview {
    OperationOutputSection { stream, showOutput in
        HStack {
            Button("Action 1") {
                showOutput()
                print("Would use stream: \(stream)")
            }
            Button("Action 2") {
                showOutput()
                print("Would use stream: \(stream)")
            }
        }
    }
    .padding()
    .frame(width: 400)
}
