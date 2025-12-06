import AppKit
import Client
import SwiftUI

struct DynamoDBView: View {
    var apiClient: APIClient
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var dynamoDBFileRecords: [DynamoDBFileRecord] = []
    @State private var selectedImage: NSImage?
    @State private var selectedFileName: String = ""
    @State private var showingImagePreview = false

    /// Max file size for DynamoDB (400KB limit, minus overhead for base64 encoding and metadata)
    private let maxFileSize = 290_000

    var body: some View {
        VStack(spacing: 12) {
            // Toolbar
            HStack {
                Button(action: {
                    selectAndUploadFile()
                }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
                .help("Upload File")

                Spacer()

                Button(action: {
                    Task {
                        await loadDynamoDBFileRecords()
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

            // File Records List
            if dynamoDBFileRecords.isEmpty && !isLoading {
                Text("No file records yet")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(dynamoDBFileRecords) { record in
                    HStack {
                        Image(systemName: iconForFile(record.fileName))
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.fileName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(formatFileSize(record.fileSize))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if isImageFile(record.fileName) {
                            Button(action: {
                                Task {
                                    await previewImage(record)
                                }
                            }) {
                                Image(systemName: "eye")
                            }
                            .buttonStyle(.borderless)
                            .help("Preview")
                        }
                        Button(action: {
                            Task {
                                await downloadFile(record)
                            }
                        }) {
                            Image(systemName: "arrow.down.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Download")
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            Task {
                                await deleteDynamoDBFileRecord(record)
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
        .sheet(isPresented: $showingImagePreview) {
            if let selectedImage = selectedImage {
                ImagePreviewView(image: selectedImage, fileName: selectedFileName)
            }
        }
        .task {
            await loadDynamoDBFileRecords()
        }
    }

    private func iconForFile(_ fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif":
            return "photo"
        case "pdf":
            return "doc.text"
        case "txt", "md":
            return "doc.plaintext"
        case "zip", "tar", "gz":
            return "archivebox"
        default:
            return "doc"
        }
    }

    private func isImageFile(_ fileName: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif"].contains(ext)
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func contentType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "pdf":
            return "application/pdf"
        case "txt":
            return "text/plain"
        case "json":
            return "application/json"
        case "zip":
            return "application/zip"
        default:
            return "application/octet-stream"
        }
    }

    private func selectAndUploadFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let fileURL = panel.url {
            Task {
                isLoading = true
                errorMessage = nil

                do {
                    var data = try Data(contentsOf: fileURL)
                    let fileName = fileURL.lastPathComponent
                    var mimeType = contentType(for: fileName)

                    // Downsample images if they exceed the max size
                    if isImageFile(fileName) && data.count > maxFileSize {
                        if let downsampledData = downsampleImage(data: data, maxSize: maxFileSize) {
                            data = downsampledData
                            mimeType = "image/jpeg"
                        }
                    }

                    // Check final size
                    if data.count > maxFileSize {
                        errorMessage = "File too large (\(formatFileSize(data.count))). Max size is \(formatFileSize(maxFileSize))."
                        isLoading = false
                        return
                    }

                    _ = try await apiClient.createDynamoDBFileRecord(fileName: fileName, contentType: mimeType, data: data)
                    await loadDynamoDBFileRecords()
                } catch {
                    errorMessage = error.localizedDescription
                }

                isLoading = false
            }
        }
    }

    private func downsampleImage(data: Data, maxSize: Int) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        var quality: CGFloat = 0.8
        var currentSize = image.size
        var resultData: Data?

        // Try progressively lower quality and smaller sizes until we're under the limit
        while quality >= 0.1 {
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            bitmapRep.size = currentSize

            if let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality]) {
                if jpegData.count <= maxSize {
                    return jpegData
                }
                resultData = jpegData
            }

            // Reduce quality first
            if quality > 0.3 {
                quality -= 0.1
            } else {
                // Then reduce dimensions by 20%
                quality = 0.8
                currentSize = NSSize(width: currentSize.width * 0.8, height: currentSize.height * 0.8)

                // Create a resized image
                let resizedImage = NSImage(size: currentSize)
                resizedImage.lockFocus()
                image.draw(in: NSRect(origin: .zero, size: currentSize),
                          from: NSRect(origin: .zero, size: image.size),
                          operation: .copy,
                          fraction: 1.0)
                resizedImage.unlockFocus()

                guard let resizedCGImage = resizedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    break
                }

                let resizedBitmapRep = NSBitmapImageRep(cgImage: resizedCGImage)
                resizedBitmapRep.size = currentSize

                if let jpegData = resizedBitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality]) {
                    if jpegData.count <= maxSize {
                        return jpegData
                    }
                    resultData = jpegData
                }

                // Give up if image is too small
                if currentSize.width < 100 || currentSize.height < 100 {
                    break
                }
            }
        }

        return resultData
    }

    private func loadDynamoDBFileRecords() async {
        isLoading = true
        errorMessage = nil

        do {
            dynamoDBFileRecords = try await apiClient.listDynamoDBFileRecords()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func downloadFile(_ record: DynamoDBFileRecord) async {
        isLoading = true
        errorMessage = nil

        do {
            guard let data = Data(base64Encoded: record.data) else {
                errorMessage = "Invalid file data"
                isLoading = false
                return
            }

            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = record.fileName
            savePanel.canCreateDirectories = true

            if savePanel.runModal() == .OK, let url = savePanel.url {
                try data.write(to: url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func previewImage(_ record: DynamoDBFileRecord) async {
        isLoading = true
        errorMessage = nil

        guard let data = Data(base64Encoded: record.data) else {
            errorMessage = "Invalid file data"
            isLoading = false
            return
        }

        if let image = NSImage(data: data) {
            selectedImage = image
            selectedFileName = record.fileName
            showingImagePreview = true
        } else {
            errorMessage = "Failed to load image"
        }

        isLoading = false
    }

    private func deleteDynamoDBFileRecord(_ record: DynamoDBFileRecord) async {
        isLoading = true
        errorMessage = nil

        do {
            try await apiClient.deleteDynamoDBFileRecord(id: record.id)
            await loadDynamoDBFileRecords()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    DynamoDBView(apiClient: .preview)
}
