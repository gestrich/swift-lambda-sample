import SwiftUI
import CLIKit

/// Tutorial view showcasing CLIKit with the ls command
struct CLIKitTutorialView: View {
    @State private var files: [FileEntry] = []
    @State private var isRunning = false
    @State private var hasRun = false
    @State private var errorMessage: String?
    @State private var currentPath: String
    @State private var rawOutput: String = ""

    // Options state
    @State private var showLongFormat = true
    @State private var showAll = true
    @State private var showAlmostAll = false
    @State private var humanReadable = false
    @State private var sortBySize = false
    @State private var sortByTime = false
    @State private var reverseSort = false
    @State private var showInode = false
    @State private var classify = false
    @State private var recursive = false

    private let cliService = CLIService.shared

    init() {
        // Default to home directory for a better demo experience
        _currentPath = State(initialValue: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    /// Build the command string for display
    private var commandString: String {
        var flags: [String] = []
        if showLongFormat { flags.append("-l") }
        if showAll { flags.append("-a") }
        if showAlmostAll { flags.append("-A") }
        if humanReadable { flags.append("-h") }
        if sortBySize { flags.append("-S") }
        if sortByTime { flags.append("-t") }
        if reverseSort { flags.append("-r") }
        if showInode { flags.append("-i") }
        if classify { flags.append("-F") }
        if recursive { flags.append("-R") }

        let flagStr = flags.isEmpty ? "" : " " + flags.joined(separator: " ")
        return "ls\(flagStr) \(currentPath)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("CLIKit Tutorial")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Learn how to use CLIKit to build type-safe CLI wrappers with structured output")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Step 1: Define the command
                TutorialSection(number: 1, title: "Define the Command") {
                    Text("First, define the CLI program and command using macros:")
                        .font(.callout)

                    CodeBlock("""
                    @CLIProgram
                    struct Ls {
                        @CLICommand("")
                        struct List {
                            @Flag("-l") var longFormat: Bool = false
                            @Flag("-a") var all: Bool = false
                            @Flag("-h") var humanReadable: Bool = false
                            @Flag("-S") var sortBySize: Bool = false
                            @Flag("-t") var sortByTime: Bool = false
                            @Flag("-r") var reverse: Bool = false
                            @Positional var path: String?
                        }
                    }
                    """)
                }

                // Step 2: Define the parser
                TutorialSection(number: 2, title: "Create a Parser") {
                    Text("Define a parser to transform raw output into structured data:")
                        .font(.callout)

                    CodeBlock("""
                    struct LsParser: CLIOutputParser {
                        func parse(_ output: String) throws -> [FileEntry] {
                            // Parse ls -l output into FileEntry structs
                            ...
                        }
                    }
                    """)
                }

                // Step 3: Execute with parser
                TutorialSection(number: 3, title: "Execute with Parser") {
                    Text("Run the command and get structured output:")
                        .font(.callout)

                    CodeBlock("""
                    let command = Ls.List(longFormat: true, path: ".")
                    let files = try await service.execute(command, parser: LsParser())
                    // files is [FileEntry], not String!
                    """)
                }

                Divider()

                // Live Demo
                VStack(alignment: .leading, spacing: 16) {
                    Text("Live Demo")
                        .font(.title2)
                        .fontWeight(.semibold)

                    // Path input
                    HStack {
                        Text("Path:")
                            .font(.callout)
                            .frame(width: 50, alignment: .leading)
                        TextField("Directory path", text: $currentPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    // Options
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Options")
                            .font(.headline)

                        // Display options
                        OptionsRow(title: "Display") {
                            OptionToggle(label: "-l", description: "Long format", isOn: $showLongFormat)
                            OptionToggle(label: "-h", description: "Human sizes", isOn: $humanReadable)
                            OptionToggle(label: "-i", description: "Show inode", isOn: $showInode)
                            OptionToggle(label: "-F", description: "Classify", isOn: $classify)
                        }

                        // File selection
                        OptionsRow(title: "Files") {
                            OptionToggle(label: "-a", description: "All files", isOn: $showAll)
                            OptionToggle(label: "-A", description: "Almost all", isOn: $showAlmostAll)
                            OptionToggle(label: "-R", description: "Recursive", isOn: $recursive)
                        }

                        // Sorting
                        OptionsRow(title: "Sort") {
                            OptionToggle(label: "-S", description: "By size", isOn: $sortBySize)
                            OptionToggle(label: "-t", description: "By time", isOn: $sortByTime)
                            OptionToggle(label: "-r", description: "Reverse", isOn: $reverseSort)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)

                    // Command preview
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Generated Command:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(commandString)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.blue)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                    }

                    // Run button
                    HStack {
                        Button(action: runCommand) {
                            HStack {
                                if isRunning {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "play.fill")
                                }
                                Text(isRunning ? "Running..." : "Run Command")
                            }
                            .frame(minWidth: 140)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning)

                        if hasRun {
                            Button("Clear Results") {
                                files = []
                                rawOutput = ""
                                hasRun = false
                                errorMessage = nil
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }

                    // Results
                    if hasRun && errorMessage == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Structured Output")
                                    .font(.headline)
                                Spacer()
                                Text("\(files.count) items")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if files.isEmpty {
                                Text("No files found")
                                    .foregroundColor(.secondary)
                                    .italic()
                            } else {
                                FileListView(files: files)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            }
            .padding()
        }
    }

    private func runCommand() {
        isRunning = true
        errorMessage = nil

        Task {
            do {
                let command = Ls.List(
                    longFormat: showLongFormat,
                    all: showAll,
                    almostAll: showAlmostAll,
                    sortBySize: sortBySize,
                    sortByTime: sortByTime,
                    reverse: reverseSort,
                    humanReadable: humanReadable,
                    showInode: showInode,
                    classify: classify,
                    recursive: recursive,
                    path: currentPath
                )

                // Only parse with LsParser if long format is enabled
                if showLongFormat {
                    let result = try await cliService.execute(command, parser: LsParser())
                    await MainActor.run {
                        files = result
                        hasRun = true
                        isRunning = false
                    }
                } else {
                    // Without -l, just show raw output
                    let result = try await cliService.execute(command)
                    await MainActor.run {
                        // Create simple file entries from names
                        files = result.components(separatedBy: .newlines)
                            .filter { !$0.isEmpty }
                            .map { name in
                                FileEntry(
                                    name: name,
                                    permissions: "",
                                    links: 0,
                                    owner: "",
                                    group: "",
                                    size: 0,
                                    dateString: "",
                                    isDirectory: name.hasSuffix("/"),
                                    isSymlink: name.hasSuffix("@"),
                                    isExecutable: name.hasSuffix("*")
                                )
                            }
                        hasRun = true
                        isRunning = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    files = []
                    hasRun = true
                    isRunning = false
                }
            }
        }
    }
}

// MARK: - Option Controls

struct OptionsRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)

            HStack(spacing: 16) {
                content
            }

            Spacer()
        }
    }
}

struct OptionToggle: View {
    let label: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .frame(minWidth: 100, alignment: .leading)
    }
}

// MARK: - Supporting Views

struct TutorialSection<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.blue)
                    .clipShape(Circle())

                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            content
                .padding(.leading, 40)
        }
    }
}

struct CodeBlock: View {
    let code: String

    init(_ code: String) {
        self.code = code
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

struct FileListView: View {
    let files: [FileEntry]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("Name")
                    .frame(minWidth: 200, alignment: .leading)
                Text("Size")
                    .frame(width: 80, alignment: .trailing)
                Text("Owner")
                    .frame(width: 80, alignment: .leading)
                Text("Permissions")
                    .frame(width: 100, alignment: .leading)
                Text("Modified")
                    .frame(width: 120, alignment: .leading)
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // File rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(files) { file in
                        FileRowView(file: file)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

struct FileRowView: View {
    let file: FileEntry

    var body: some View {
        HStack(spacing: 0) {
            // Name with icon
            HStack(spacing: 6) {
                Text(file.icon)
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 200, alignment: .leading)

            // Size
            Text(file.isDirectory ? "-" : file.humanSize)
                .frame(width: 80, alignment: .trailing)
                .foregroundColor(.secondary)

            // Owner
            Text(file.owner)
                .frame(width: 80, alignment: .leading)
                .foregroundColor(.secondary)

            // Permissions
            Text(file.permissions)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 100, alignment: .leading)
                .foregroundColor(.secondary)

            // Date
            Text(file.dateString)
                .frame(width: 120, alignment: .leading)
                .foregroundColor(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(file.isDirectory ? Color.blue.opacity(0.05) : Color.clear)
    }
}

#Preview {
    CLIKitTutorialView()
        .frame(width: 700, height: 800)
}
