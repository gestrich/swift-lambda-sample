import AppKit
import Client
import SwiftUI

struct S3View: View {
    @Environment(APIClient.self) var apiClient
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var uploadedFiles: [String] = []
    @State private var selectedImage: NSImage?
    @State private var showingImagePreview = false

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
                        await loadFiles()
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

            // Files List
            if uploadedFiles.isEmpty && !isLoading {
                Text("No files uploaded yet")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(uploadedFiles, id: \.self) { fileName in
                    HStack {
                        Image(systemName: iconForFile(fileName))
                            .foregroundColor(.blue)
                        Text(fileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if fileName.lowercased().hasSuffix(".png") ||
                            fileName.lowercased().hasSuffix(".jpg") ||
                            fileName.lowercased().hasSuffix(".jpeg") {
                            Button(action: {
                                Task {
                                    await previewImage(fileName)
                                }
                            }) {
                                Image(systemName: "eye")
                            }
                            .buttonStyle(.borderless)
                            .help("Preview")
                        }
                        Button(action: {
                            Task {
                                await downloadFile(fileName)
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
                                await deleteFile(fileName)
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
                    _ = try await apiClient.uploadFile(fileName: fileName, data: data)
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
            uploadedFiles = try await apiClient.listFiles()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func downloadFile(_ fileName: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await apiClient.downloadFile(fileName: fileName)

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
            let data = try await apiClient.downloadFile(fileName: fileName)
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
            _ = try await apiClient.deleteFile(fileName: fileName)
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
    S3View()
}
