import AppKit
import Client
import SwiftUI

struct FileView: View {
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var uploadedFiles: [String] = []
    @State private var selectedImage: NSImage?
    @State private var showingImagePreview = false

    var body: some View {
        VStack(spacing: 20) {
            Text("S3 File Operations")
                .font(.title)
                .padding(.top)

            Divider()

            // Upload Section
            VStack(spacing: 15) {
                Text("Upload File")
                    .font(.headline)

                Button("Upload") {
                    selectAndUploadFile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal)

            Divider()

            // Uploaded Files Section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Uploaded Files")
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        Task {
                            await loadFiles()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isLoading)
                }
                .padding(.horizontal)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }

                if uploadedFiles.isEmpty && !isLoading {
                    Text("No files uploaded yet")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    List(uploadedFiles, id: \.self) { fileName in
                        HStack {
                            Image(systemName: iconForFile(fileName))
                                .foregroundColor(.blue)
                            Text(fileName)
                            Spacer()
                            if fileName.lowercased().hasSuffix(".png") ||
                               fileName.lowercased().hasSuffix(".jpg") ||
                               fileName.lowercased().hasSuffix(".jpeg") {
                                Button("Preview") {
                                    Task {
                                        await previewImage(fileName)
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                            Button("Download") {
                                Task {
                                    await downloadFile(fileName)
                                }
                            }
                            .buttonStyle(.borderless)
                            Button("Delete") {
                                Task {
                                    await deleteFile(fileName)
                                }
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.red)
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.inset)
                }
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingImagePreview) {
            if let selectedImage = selectedImage {
                ImagePreviewView(image: selectedImage, fileName: "Preview")
            }
        }
        .task {
            await loadFiles()
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
                    let data = try Data(contentsOf: fileURL)
                    let fileName = fileURL.lastPathComponent
                    _ = try await APIClient.shared.uploadFile(fileName: fileName, data: data)
                    await loadFiles()
                } catch {
                    errorMessage = error.localizedDescription
                }

                isLoading = false
            }
        }
    }

    private func loadFiles() async {
        isLoading = true
        errorMessage = nil

        do {
            uploadedFiles = try await APIClient.shared.listFiles()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func downloadFile(_ fileName: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await APIClient.shared.downloadFile(fileName: fileName)

            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = fileName
            savePanel.canCreateDirectories = true

            if savePanel.runModal() == .OK, let url = savePanel.url {
                try data.write(to: url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func previewImage(_ fileName: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await APIClient.shared.downloadFile(fileName: fileName)
            if let image = NSImage(data: data) {
                selectedImage = image
                showingImagePreview = true
            } else {
                errorMessage = "Failed to load image"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func deleteFile(_ fileName: String) async {
        isLoading = true
        errorMessage = nil

        do {
            _ = try await APIClient.shared.deleteFile(fileName: fileName)
            await loadFiles()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct ImagePreviewView: View {
    let image: NSImage
    let fileName: String

    var body: some View {
        VStack {
            Text(fileName)
                .font(.headline)
                .padding()

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 600, maxHeight: 600)
                .padding()
        }
        .frame(minWidth: 400, minHeight: 400)
    }
}

#Preview {
    FileView()
}
