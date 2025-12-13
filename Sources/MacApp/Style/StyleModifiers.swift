import SwiftUI

// MARK: - Content Styling

extension View {
    /// Style for section headers
    func sectionHeader() -> some View {
        self
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
    }

    /// Style for subsection headers
    func subheader() -> some View {
        self
            .font(.headline)
            .foregroundStyle(.primary)
    }

    /// Style for body text
    func bodyText() -> some View {
        self
            .font(.body)
            .foregroundStyle(.secondary)
            .lineSpacing(4)
    }

    /// Style for caption/detail text
    func captionText() -> some View {
        self
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    /// Card-style container for content sections
    func card() -> some View {
        self
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Status Badge Styling

extension View {
    /// Badge for implemented status (green checkmark)
    func statusBadgeImplemented() -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            self
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    /// Badge for partial status (yellow warning)
    func statusBadgePartial() -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            self
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    /// Badge for not implemented status (gray circle)
    func statusBadgeNotImplemented() -> some View {
        HStack(spacing: 4) {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
            self
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
