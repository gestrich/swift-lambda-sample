import CLIKit
import SwiftDeploy
import SwiftUI

/// Test view demonstrating operation-scoped output streams.
/// Shows how clients can create, pass, and consume their own output streams
/// to get isolated output from specific operations.
struct TestOutputStreamView: View {
    @Environment(AppModel.self) var model

    // Operation A: Client-owned stream
    @State private var operationAOutput: CLIOutputStream?
    @State private var operationARunning = false

    // Operation B: Client-owned stream (for concurrent testing)
    @State private var operationBOutput: CLIOutputStream?
    @State private var operationBRunning = false

    // Track which global stream we're showing
    @State private var showGlobalStream = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Operation-Scoped Output Streams Test")
                .font(.headline)

            Text("Test that operations receive only their own output, not output from other concurrent operations.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            // Operation A Section
            operationSection(
                title: "Operation A",
                label: "OperationA",
                stream: $operationAOutput,
                isRunning: $operationARunning,
                accentColor: .blue
            )

            Divider()

            // Operation B Section
            operationSection(
                title: "Operation B",
                label: "OperationB",
                stream: $operationBOutput,
                isRunning: $operationBRunning,
                accentColor: .green
            )

            Divider()

            // Global Stream Toggle
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Global Stream")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Toggle("Show", isOn: $showGlobalStream)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                if showGlobalStream {
                    Text("Shows ALL output from both operations (existing behavior)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    StreamingTextView(
                        streamProvider: { await model.remoteService.cliService.outputStream() }
                    )
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Operation Section

    @ViewBuilder
    private func operationSection(
        title: String,
        label: String,
        stream: Binding<CLIOutputStream?>,
        isRunning: Binding<Bool>,
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(accentColor)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if isRunning.wrappedValue {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                Button("Run Test") {
                    runOperation(label: label, stream: stream, isRunning: isRunning)
                }
                .disabled(isRunning.wrappedValue)
            }

            Text("Output should show only commands with [\(label)] prefix")
                .font(.caption)
                .foregroundColor(.secondary)

            // Operation-specific output panel
            if let outputStream = stream.wrappedValue {
                StreamingTextView(
                    streamProvider: { await outputStream.makeStream() }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(accentColor.opacity(0.5), lineWidth: 2)
                )
            } else {
                Text("No output yet - click 'Run Test' to start")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
            }
        }
    }

    // MARK: - Run Operation

    private func runOperation(
        label: String,
        stream: Binding<CLIOutputStream?>,
        isRunning: Binding<Bool>
    ) {
        // 1. Client CREATES the stream
        let newStream = CLIOutputStream()
        stream.wrappedValue = newStream
        isRunning.wrappedValue = true

        Task {
            defer {
                // 4. Client FINISHES the stream
                Task {
                    await newStream.finishAll()
                    await MainActor.run {
                        isRunning.wrappedValue = false
                    }
                }
            }

            // 2. Client creates service and PASSES stream to service calls
            let testService = TestCLIService(cliService: model.remoteService.cliService)

            do {
                // 3. Service runs commands, outputting to the client's stream
                try await testService.runMultiStepOperation(
                    label: label,
                    steps: 4,
                    output: newStream
                )
            } catch {
                print("Operation \(label) failed: \(error)")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let model = AppModel()
    return TestOutputStreamView()
        .environment(model)
        .frame(width: 600, height: 800)
}
