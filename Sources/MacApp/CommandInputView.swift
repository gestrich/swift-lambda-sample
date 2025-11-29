import SwiftUI
import AppKit

/// A command input field with autocomplete suggestions
struct CommandInputView: View {
    @Binding var text: String
    let onSubmit: (String) -> Void

    @State private var selectedIndex: Int = 0
    @State private var showSuggestions = false
    @State private var isFocused = false

    /// Known commands with their common arguments
    private let commandSuggestions: [(command: String, description: String, args: [[String]])] = [
        ("ls", "List directory contents", [["-la"], ["-lah"], ["-R"], []]),
        ("pwd", "Print working directory", [[]]),
        ("cd", "Change directory", [["~"], [".."], ["."]]),
        ("cat", "Concatenate and print files", []),
        ("echo", "Display text", [["$PATH"], ["$HOME"]]),
        ("date", "Display date and time", [["+%Y-%m-%d"], []]),
        ("whoami", "Print current user", [[]]),
        ("hostname", "Print hostname", [[]]),
        ("uname", "Print system info", [["-a"], ["-m"], []]),
        ("df", "Disk free space", [["-h"], []]),
        ("du", "Disk usage", [["-sh"], ["-h"]]),
        ("ps", "Process status", [["aux"], ["-ef"], []]),
        ("top", "Display processes", [["-l", "1"], []]),
        ("env", "Environment variables", [[]]),
        ("which", "Locate a program", []),
        ("file", "Determine file type", []),
        ("head", "Output first lines", [["-n", "10"]]),
        ("tail", "Output last lines", [["-n", "10"], ["-f"]]),
        ("wc", "Word count", [["-l"], ["-w"], []]),
        ("grep", "Search patterns", [["-r"], ["-i"]]),
        ("find", "Find files", [["."], ["-name"]]),
        ("mkdir", "Make directory", [["-p"]]),
        ("rm", "Remove files", [["-rf"], ["-i"]]),
        ("cp", "Copy files", [["-r"]]),
        ("mv", "Move files", []),
        ("touch", "Create empty file", []),
        ("chmod", "Change permissions", []),
        ("chown", "Change owner", []),
        ("curl", "Transfer data", [["-s"], ["-I"], ["-X", "GET"]]),
        ("git", "Version control", [["status"], ["log", "--oneline"], ["branch"], ["diff"]]),
        ("swift", "Swift compiler", [["--version"], ["build"], ["test"]]),
        ("docker", "Container platform", [["ps"], ["images"], ["ps", "-a"]]),
    ]

    /// Current suggestions based on input
    private var suggestions: [String] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let parts = trimmed.components(separatedBy: " ")
        let command = parts[0].lowercased()

        // If we're still typing the command (no space yet)
        if parts.count == 1 && !text.hasSuffix(" ") {
            return commandSuggestions
                .filter { $0.command.hasPrefix(command) }
                .prefix(8)
                .map { $0.command }
        }

        // If we have a command, suggest arguments
        if let cmdInfo = commandSuggestions.first(where: { $0.command == command }) {
            let currentArgs = Array(parts.dropFirst()).joined(separator: " ")
            return cmdInfo.args
                .map { "\(command) \($0.joined(separator: " "))".trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix(trimmed) || currentArgs.isEmpty }
                .prefix(6)
                .map { $0 }
        }

        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Input field
            HStack(spacing: 8) {
                Text("$")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)

                CommandTextField(
                    text: $text,
                    isFocused: $isFocused,
                    onTab: {
                        if showSuggestions && !suggestions.isEmpty {
                            text = suggestions[selectedIndex]
                            if !text.contains(" ") {
                                text += " "
                            }
                            return true
                        }
                        return false
                    },
                    onUpArrow: {
                        if showSuggestions && !suggestions.isEmpty {
                            selectedIndex = max(selectedIndex - 1, 0)
                            return true
                        }
                        return false
                    },
                    onDownArrow: {
                        if showSuggestions && !suggestions.isEmpty {
                            selectedIndex = min(selectedIndex + 1, suggestions.count - 1)
                            return true
                        }
                        return false
                    },
                    onEscape: {
                        showSuggestions = false
                        return true
                    },
                    onSubmit: {
                        submitCommand()
                    }
                )

                if !text.isEmpty {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
            )

            // Suggestions dropdown
            if showSuggestions && !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                        SuggestionRow(
                            text: suggestion,
                            description: commandSuggestions.first { suggestion.hasPrefix($0.command) }?.description,
                            isSelected: index == selectedIndex
                        )
                        .onTapGesture {
                            text = suggestion
                            if !suggestion.contains(" ") {
                                text += " "
                            }
                            showSuggestions = false
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .padding(.top, 4)
            }
        }
        .onChange(of: text) { _, _ in
            selectedIndex = 0
            showSuggestions = !suggestions.isEmpty && isFocused
        }
        .onChange(of: isFocused) { _, focused in
            showSuggestions = focused && !suggestions.isEmpty
        }
    }

    private func submitCommand() {
        let command = text.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }
        onSubmit(command)
        text = ""
        showSuggestions = false
    }
}

/// A single suggestion row
private struct SuggestionRow: View {
    let text: String
    let description: String?
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(text)
                .font(.system(.body, design: .monospaced))

            if let desc = description {
                Spacer()
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Custom NSTextField for Tab key handling

/// NSViewRepresentable wrapper for NSTextField that can intercept Tab key
private struct CommandTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onTab: () -> Bool
    let onUpArrow: () -> Bool
    let onDownArrow: () -> Bool
    let onEscape: () -> Bool
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = CustomTextField()
        textField.delegate = context.coordinator
        textField.stringValue = text
        textField.placeholderString = "Enter command..."
        textField.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.customDelegate = context.coordinator
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject, NSTextFieldDelegate, CustomTextFieldDelegate {
        var parent: CommandTextField

        init(_ parent: CommandTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isFocused = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.isFocused = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }

        // CustomTextFieldDelegate
        func handleTab() -> Bool {
            parent.onTab()
        }

        func handleUpArrow() -> Bool {
            parent.onUpArrow()
        }

        func handleDownArrow() -> Bool {
            parent.onDownArrow()
        }

        func handleEscape() -> Bool {
            parent.onEscape()
        }
    }
}

/// Protocol for custom key handling
@MainActor
private protocol CustomTextFieldDelegate: AnyObject {
    func handleTab() -> Bool
    func handleUpArrow() -> Bool
    func handleDownArrow() -> Bool
    func handleEscape() -> Bool
}

/// Custom NSTextField that intercepts Tab and arrow keys
private class CustomTextField: NSTextField {
    weak var customDelegate: CustomTextFieldDelegate?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48: // Tab
            if customDelegate?.handleTab() == true {
                return
            }
        case 126: // Up arrow
            if customDelegate?.handleUpArrow() == true {
                return
            }
        case 125: // Down arrow
            if customDelegate?.handleDownArrow() == true {
                return
            }
        case 53: // Escape
            if customDelegate?.handleEscape() == true {
                return
            }
        default:
            break
        }
        super.keyDown(with: event)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var text = ""

        var body: some View {
            VStack {
                CommandInputView(text: $text) { command in
                    print("Submitted: \(command)")
                }
                Spacer()
            }
            .padding()
            .frame(width: 500, height: 300)
        }
    }

    return PreviewWrapper()
}
