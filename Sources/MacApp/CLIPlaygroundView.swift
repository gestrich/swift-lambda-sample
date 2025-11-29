import SwiftUI
import SwiftDeploy

/// Playground view for testing CLI commands
struct CLIPlaygroundView: View {
    @State private var commandText = ""
    @State private var outputLines: [String] = []
    @State private var isRunning = false

    private let cliService = CLIService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CLI Playground")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Type a command and press Enter. Use Tab to autocomplete, arrow keys to navigate suggestions.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Command input
            CommandInputView(text: $commandText) { command in
                runCommand(command)
            }
            .disabled(isRunning)

            // Output view
            StreamingTextView(
                lines: outputLines,
                isClearDisabled: isRunning
            ) {
                outputLines.removeAll()
            }

            Spacer()
        }
        .padding()
    }

    private func runCommand(_ commandString: String) {
        let parts = commandString.components(separatedBy: " ").filter { !$0.isEmpty }
        guard let command = parts.first else { return }
        let arguments = Array(parts.dropFirst())

        isRunning = true
        outputLines.append("$ \(commandString)")

        Task {
            do {
                let result = try await cliService.execute(
                    command: command,
                    arguments: arguments,
                    printCommand: false
                )

                await MainActor.run {
                    // Add stdout lines
                    let lines = result.stdout.components(separatedBy: "\n")
                    for line in lines where !line.isEmpty {
                        outputLines.append(line)
                    }

                    // Add stderr if any
                    if !result.stderr.isEmpty {
                        let errorLines = result.stderr.components(separatedBy: "\n")
                        for line in errorLines where !line.isEmpty {
                            outputLines.append("⚠️ \(line)")
                        }
                    }

                    // Only show error status
                    if !result.isSuccess {
                        outputLines.append("❌ Failed (exit code: \(result.exitCode))")
                    }

                    outputLines.append("")
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    outputLines.append("❌ Error: \(error.localizedDescription)")
                    outputLines.append("")
                    isRunning = false
                }
            }
        }
    }
}

#Preview {
    CLIPlaygroundView()
        .frame(width: 600, height: 500)
}
