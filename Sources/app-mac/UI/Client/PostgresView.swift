import d_sdk_client
import SwiftUI

/// PostgreSQL section view for use in ClientView
struct PostgresView: View {
    var apiClient: APIClient
    @State private var users: [User] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreateUser = false
    @State private var selectedUser: User?
    @State private var isCreatingSampleUser = false

    var body: some View {
        VStack(spacing: 12) {
            // Toolbar
            HStack {
                Button(action: {
                    showingCreateUser = true
                }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
                .help("Add User")

                Button(action: {
                    Task {
                        await createSampleUser()
                    }
                }) {
                    if isCreatingSampleUser {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Label("Sample User", systemImage: "person.badge.plus")
                    }
                }
                .disabled(isLoading || isCreatingSampleUser)
                .help("Create sample user for \(apiClient.serviceName)")

                Button(action: {
                    Task {
                        await initializeDatabase()
                    }
                }) {
                    Text("Initialize DB")
                }
                .disabled(isLoading)

                Spacer()

                Button(action: {
                    Task {
                        await loadUsers()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Divider()

            // User List
            if users.isEmpty && !isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                    Text("No users found")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("Add a user or Initialize DB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(users) { user in
                    UserRowView(user: user)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedUser = user
                        }
                        .contextMenu {
                            Button("Edit") {
                                selectedUser = user
                            }
                            Button("Delete", role: .destructive) {
                                Task {
                                    await deleteUser(user)
                                }
                            }
                        }
                }
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showingCreateUser) {
            UserFormView(apiClient: apiClient, mode: .create) { _ in
                showingCreateUser = false
                Task {
                    await loadUsers()
                }
            }
        }
        .sheet(item: $selectedUser) { user in
            UserFormView(apiClient: apiClient, mode: .edit(user)) { _ in
                selectedUser = nil
                Task {
                    await loadUsers()
                }
            }
        }
        .task {
            await loadUsers()
        }
    }

    private func loadUsers() async {
        isLoading = true
        errorMessage = nil

        do {
            users = try await apiClient.listUsers()
        } catch {
            errorMessage = error.localizedDescription
            users = []
        }

        isLoading = false
    }

    private func deleteUser(_ user: User) async {
        guard let userId = user.id else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await apiClient.deleteUser(id: userId)
            await loadUsers()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func initializeDatabase() async {
        isLoading = true
        errorMessage = nil

        do {
            _ = try await apiClient.initializeDatabase()
            await loadUsers()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func createSampleUser() async {
        isCreatingSampleUser = true
        errorMessage = nil

        do {
            _ = try await apiClient.createSampleUser()
            await loadUsers()
        } catch {
            errorMessage = error.localizedDescription
        }

        isCreatingSampleUser = false
    }
}

struct UserCardView: View {
    let user: User

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with name and nickname
            HStack(alignment: .top) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(avatarColor)
                        .frame(width: 44, height: 44)
                    Text(initials)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(user.firstName) \(user.lastName)")
                        .font(.headline)

                    if !user.nickName.isEmpty {
                        Text(user.nickName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            Divider()

            // Contact info grid
            VStack(alignment: .leading, spacing: 6) {
                UserInfoRow(icon: "envelope.fill", label: "Email", value: user.email)

                if !user.phone.isEmpty {
                    UserInfoRow(icon: "phone.fill", label: "Phone", value: user.phone)
                }

                if !user.slackID.isEmpty {
                    UserInfoRow(icon: "number", label: "Slack ID", value: user.slackID)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private var initials: String {
        let first = user.firstName.prefix(1).uppercased()
        let last = user.lastName.prefix(1).uppercased()
        return "\(first)\(last)"
    }

    private var avatarColor: Color {
        // Generate a consistent color based on the user's name
        let hash = abs(user.email.hashValue)
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo]
        return colors[hash % colors.count]
    }
}

struct UserInfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(value)
                .font(.callout)
                .foregroundColor(.primary)
        }
    }
}

// Keep old name for compatibility but use new design
struct UserRowView: View {
    let user: User

    var body: some View {
        UserCardView(user: user)
    }
}

#Preview {
    PostgresView(apiClient: .preview)
}
