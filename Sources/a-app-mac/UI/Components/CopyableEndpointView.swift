import AppKit
import SwiftUI

/// A read-only endpoint display with a copy button
struct CopyableEndpointView: View {
    let label: String
    let endpoint: String
    let helpText: String

    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Text(endpoint)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )

                Button(action: copyToClipboard) {
                    if showCopied {
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "doc.on.doc")
                    }
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
            }

            Text(helpText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(endpoint, forType: .string)

        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }
}
