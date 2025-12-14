import CLIKit
import SwiftUI

/// A reusable component for displaying operation output with action buttons.
/// The view owns a persistent CLIOutputStream that accumulates output across operations.
/// Output view is hidden until content is received.
///
/// Usage:
/// ```swift
/// OperationOutputSection { stream in
///     Button("Deploy") {
///         Task { try? await service.deploy(output: stream) }
///     }
///     Button("Destroy") {
///         Task { try? await service.destroy(output: stream) }
///     }
/// }
/// ```
struct OperationOutputSection<Actions: View>: View {
    /// Persistent output stream owned by this view - accumulates across operations
    @State private var output = CLIOutputStream()

    /// Track whether we have output to show
    @State private var hasOutput = false

    /// Builder for action buttons that receive the output stream
    let actions: (CLIOutputStream) -> Actions

    init(@ViewBuilder actions: @escaping (CLIOutputStream) -> Actions) {
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            actions(output)

            if hasOutput {
                StreamingTextView(
                    streamProvider: { await output.makeStream() }
                )
            }
        }
        .task {
            // Poll for output (the stream will update hasOutput when content arrives)
            while !Task.isCancelled {
                let outputHasContent = await output.hasOutput
                if outputHasContent != hasOutput {
                    hasOutput = outputHasContent
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OperationOutputSection { stream in
        HStack {
            Button("Action 1") {
                print("Would use stream: \(stream)")
            }
            Button("Action 2") {
                print("Would use stream: \(stream)")
            }
        }
    }
    .padding()
    .frame(width: 400)
}
