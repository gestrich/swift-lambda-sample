import SwiftUI
import SwiftDeploy

/// Playground view for testing CLI commands
struct CLIPlaygroundView: View {
    @State private var outputLines: [String] = []
    @State private var isRunning = false

    private let cliService = CLIService.shared

    /// Demo commands to show
    private let demoCommands: [(name: String, command: String, args: [String])] = [
        ("List Files", "ls", ["-la"]),
        ("Current Directory", "pwd", []),
        ("Date", "date", []),
        ("Who Am I", "whoami", []),
        ("Disk Usage", "df", ["-h"]),
        ("Environment", "env", []),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CLI Playground")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Test CLI command execution with streaming output")
                .font(.caption)
                .foregroundColor(.secondary)

            // Command buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(demoCommands, id: \.name) { cmd in
                        Button(action: { runCommand(cmd.command, arguments: cmd.args) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "terminal")
                                Text(cmd.name)
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunning)
                    }
                }
            }

            Divider()

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

    private func runCommand(_ command: String, arguments: [String]) {
        isRunning = true
        outputLines.append("$ \(command) \(arguments.joined(separator: " "))")

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
