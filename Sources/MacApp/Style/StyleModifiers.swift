import SwiftUI

// MARK: - Expandable Row

/// Reusable expandable row with icon, title, description, and expandable details
struct ExpandableRow: View {
    let icon: String
    let title: String
    let description: String
    let details: String
    let color: Color

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .subheader()
                        Text(description)
                            .bodyText()
                    }
                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(details)
                    .bodyText()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .padding(.leading, 40)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Deployment Explainer

/// Reusable explainer banner for deployment views with tappable info
struct DeploymentExplainer: View {
    let icon: String
    let iconColor: Color
    let title: String
    let summary: String
    let details: [ExplainerDetail]

    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(iconColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(summary)
                        .bodyText()
                }

                Spacer()

                Button {
                    showingDetails = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Learn more")
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingDetails) {
            ExplainerDetailSheet(
                icon: icon,
                iconColor: iconColor,
                title: title,
                details: details
            )
        }
    }
}

struct ExplainerDetail: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let color: Color
}

private struct ExplainerDetailSheet: View {
    let icon: String
    let iconColor: Color
    let title: String
    let details: [ExplainerDetail]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(iconColor)

                Text(title)
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(details) { detail in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: detail.icon)
                                .font(.title3)
                                .foregroundStyle(detail.color)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(detail.title)
                                    .font(.headline)
                                Text(detail.description)
                                    .bodyText()
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

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
