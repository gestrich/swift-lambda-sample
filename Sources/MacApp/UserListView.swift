import Client
import SwiftUI

struct UserListView: View {
    @Environment(APIClient.self) var apiClient
    @State private var users: [User] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreateUser = false
    @State private var selectedUser: User?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Users")
                    .font(.title)
                    .padding()

                Spacer()

                Button(action: {
                    showingCreateUser = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .padding()
            }

            Divider()

            // Toolbar
            HStack {
                Button(action: {
                    Task {
                        await loadUsers()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                }
                .disabled(isLoading)

                Button(action: {
                    Task {
                        await initializeDatabase()
                    }
                }) {
                    HStack {
                        Image(systemName: "cylinder.fill")
                        Text("Initialize DB")
                    }
                }
                .disabled(isLoading)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding()

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            // User List
            if users.isEmpty && !isLoading {
                VStack(spacing: 10) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("No users found")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text("Click + to create a user or Initialize DB")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
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
                .listStyle(.inset)
            }
        }
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
            if let phone = user.phone {
                Text(phone)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

#Preview {
    UserListView()
}
