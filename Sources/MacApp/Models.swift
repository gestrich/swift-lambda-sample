import Foundation

struct User: Codable, Identifiable, Hashable {
    let id: UUID?
    let email: String
    let password: String?
    let firstName: String
    let lastName: String
    let nickName: String?
    let phone: String?
    let slackID: String?

    var displayName: String {
        if let nickName = nickName, !nickName.isEmpty {
            return nickName
        }
        return "\(firstName) \(lastName)"
    }
}

struct CreateUserRequest: Codable {
    let email: String
    let password: String
    let firstName: String
    let lastName: String
    let nickName: String?
    let phone: String?
    let slackID: String?
}

struct UpdateUserRequest: Codable {
    let email: String?
    let password: String?
    let firstName: String?
    let lastName: String?
    let nickName: String?
    let phone: String?
    let slackID: String?
}

struct FileUploadRequest: Codable {
    let fileName: String
    let data: String  // base64 encoded
}

struct FileDownloadResponse: Codable {
    let fileName: String
    let data: String  // base64 encoded
}
