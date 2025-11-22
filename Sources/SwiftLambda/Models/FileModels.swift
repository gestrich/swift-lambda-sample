import Foundation

struct FileUploadRequest: Codable {
    let fileName: String
    let data: String  // base64 encoded
}

struct FileDownloadResponse: Codable {
    let fileName: String
    let data: String  // base64 encoded
}
