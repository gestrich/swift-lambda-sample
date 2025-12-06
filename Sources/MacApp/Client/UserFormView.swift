import Client
import SwiftUI

enum UserFormMode {
    case create
    case edit(User)

    var title: String {
        switch self {
        case .create: return "Create User"
        case .edit: return "Edit User"
        }
    }

    var submitButtonTitle: String {
        switch self {
        case .create: return "Create"
        case .edit: return "Update"
        }
    }
}

struct UserFormView: View {
    var apiClient: APIClient
    let mode: UserFormMode
    let onComplete: (User?) -> Void

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var nickName: String = ""
    @State private var phone: String = ""
    @State private var slackID: String = ""

    @State private var isLoading = false
    @State private var errorMessage: String?

    init(apiClient: APIClient, mode: UserFormMode, onComplete: @escaping (User?) -> Void) {
        self.mode = mode
        self.onComplete = onComplete
        self.apiClient = apiClient
        
        if case .edit(let user) = mode {
            _email = State(initialValue: user.email)
            _firstName = State(initialValue: user.firstName)
            _lastName = State(initialValue: user.lastName)
            _nickName = State(initialValue: user.nickName)
            _phone = State(initialValue: user.phone)
            _slackID = State(initialValue: user.slackID)
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(mode.title)
                .font(.title)
                .padding(.top)

            Divider()

            ScrollView {
                VStack(spacing: 15) {
                    // Email
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Email *")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("email@example.com", text: $email)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Password (only for create)
                    if case .create = mode {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Password *")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("password", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    // First Name
                    VStack(alignment: .leading, spacing: 5) {
                        Text("First Name *")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("John", text: $firstName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Last Name
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Last Name *")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Doe", text: $lastName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Nick Name
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Nickname *")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("JD", text: $nickName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Phone
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Phone *")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("555-1234", text: $phone)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Slack ID
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Slack ID *")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("U12345678", text: $slackID)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.horizontal, 20)
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

            // Buttons
            HStack(spacing: 15) {
                Button("Cancel") {
                    onComplete(nil)
                }
                .keyboardShortcut(.cancelAction)

                Button(mode.submitButtonTitle) {
                    Task {
                        await submit()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isLoading || !isValid)
            }
            .padding()
        }
        .frame(width: 400, height: 600)
    }

    private var isValid: Bool {
        switch mode {
        case .create:
            return !email.isEmpty && !password.isEmpty && !firstName.isEmpty && !lastName.isEmpty && !nickName.isEmpty && !phone.isEmpty && !slackID.isEmpty
        case .edit:
            return !email.isEmpty && !firstName.isEmpty && !lastName.isEmpty && !nickName.isEmpty && !phone.isEmpty && !slackID.isEmpty
        }
    }

    private func submit() async {
        isLoading = true
        errorMessage = nil

        do {
            let user: User
            switch mode {
            case .create:
                let request = CreateUserRequest(
                    email: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName,
                    nickName: nickName,
                    phone: phone,
                    slackID: slackID
                )
                user = try await apiClient.createUser(request)
            case .edit(let existingUser):
                guard let userId = existingUser.id else {
                    errorMessage = "User ID not found"
                    isLoading = false
                    return
                }
                let request = UpdateUserRequest(
                    email: email,
                    password: nil,
                    firstName: firstName,
                    lastName: lastName,
                    nickName: nickName,
                    phone: phone,
                    slackID: slackID
                )
                user = try await apiClient.updateUser(id: userId, request)
            }
            onComplete(user)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

#Preview {
    UserFormView(apiClient: .preview, mode: .create) { _ in }
}
