import Client
import SwiftUI

/// PostgreSQL section view for use in ClientView
struct PostgresView: View {
    @Environment(APIClient.self) var apiClient
    @State private var users: [User] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreateUser = false
    @State private var selectedUser: User?

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
            UserFormView(mode: .create) { _ in
                showingCreateUser = false
                Task {
                    await loadUsers()
                }
            }
        }
        .sheet(item: $selectedUser) { user in
            UserFormView(mode: .edit(user)) { _ in
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
}

struct UserRowView: View {
    let user: User

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(user.displayName)
                .font(.headline)
            Text(user.email)
                .font(.subheadline)
                .foregroundColor(.secondary)
            if !user.phone.isEmpty {
                Text(user.phone)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

#Preview {
    PostgresView()
}
