import Foundation

/// Resolves the project root directory automatically based on how the app was launched.
///
/// Detection strategy:
/// 1. DerivedData: When run from Xcode, extracts workspace path from info.plist
/// 2. Repo root: Current directory contains `cdk/` and `Package.swift`
/// 3. Subdirectory: Currently inside a known project subdirectory
struct ProjectPathResolver {

    // MARK: - Public

    func resolveProjectRoot() throws -> URL {
        return try resolveFromWorkingDirectory()
    }

    // MARK: - Private

    private enum RunLocation {
        case derivedData(cwd: URL)
        case projectRoot(cwd: URL)
        case projectSubdirectory(cwd: URL, root: URL)
        case other(cwd: URL)

        static let cdkDirectoryName = "cdk"
        static let packageFileName = "Package.swift"

        init() {
            let cwd = FileManager.default.currentDirectoryPath
            let cwdURL = URL(fileURLWithPath: cwd)

            // Check if running from DerivedData (Xcode)
            if cwd.contains("/DerivedData/") {
                self = .derivedData(cwd: cwdURL)
                return
            }

            // Check if current directory is the project root
            if Self.isProjectRoot(cwdURL) {
                self = .projectRoot(cwd: cwdURL)
                return
            }

            // Check if we're inside a subdirectory of the project
            if let root = Self.findProjectRootInParents(of: cwdURL) {
                self = .projectSubdirectory(cwd: cwdURL, root: root)
                return
            }

            self = .other(cwd: cwdURL)
        }

        private static func isProjectRoot(_ url: URL) -> Bool {
            let cdkDir = url.appendingPathComponent(cdkDirectoryName)
            let packageFile = url.appendingPathComponent(packageFileName)
            return FileManager.default.fileExists(atPath: cdkDir.path) &&
                   FileManager.default.fileExists(atPath: packageFile.path)
        }

        private static func findProjectRootInParents(of url: URL) -> URL? {
            var current = url.deletingLastPathComponent()
            let root = URL(fileURLWithPath: "/")

            // Walk up the directory tree (max 10 levels to avoid infinite loops)
            for _ in 0..<10 {
                if current.path == root.path {
                    return nil
                }

                if isProjectRoot(current) {
                    return current
                }

                current = current.deletingLastPathComponent()
            }

            return nil
        }
    }

    private func resolveFromWorkingDirectory() throws -> URL {
        let location = RunLocation()

        switch location {
        case .derivedData(let cwd):
            return try resolveWorkspacePathFromDerivedData(cwd)
        case .projectRoot(let cwd):
            return cwd
        case .projectSubdirectory(_, let root):
            return root
        case .other(let cwd):
            throw ProjectPathResolutionError.noValidPathFound(
                cwd: cwd.path,
                reason: "Not run from DerivedData, project root, or project subdirectory"
            )
        }
    }

    private func resolveWorkspacePathFromDerivedData(_ url: URL) throws -> URL {
        // DerivedData structure: ~/Library/Developer/Xcode/DerivedData/{ProjectName}-{hash}/...
        // info.plist is at the {ProjectName}-{hash}/ level
        let pathSplit = url.path.components(separatedBy: "/DerivedData/")
        guard pathSplit.count == 2 else {
            throw ProjectPathResolutionError.derivedDataPathInvalid(path: url.path)
        }
        let pathBeforeDerivedData = pathSplit[0]
        let pathAfterDerivedData = pathSplit[1]

        guard let projectDir = pathAfterDerivedData.components(separatedBy: "/").first else {
            throw ProjectPathResolutionError.derivedDataPathInvalid(path: url.path)
        }

        let infoPlistURL = URL(fileURLWithPath: "\(pathBeforeDerivedData)/DerivedData/\(projectDir)/info.plist")

        guard FileManager.default.fileExists(atPath: infoPlistURL.path) else {
            throw ProjectPathResolutionError.infoPlistNotFound(path: infoPlistURL.path)
        }

        return try extractWorkspacePath(from: infoPlistURL)
    }

    private func extractWorkspacePath(from infoPlistURL: URL) throws -> URL {
        let data: Data
        do {
            data = try Data(contentsOf: infoPlistURL)
        } catch {
            throw ProjectPathResolutionError.infoPlistReadFailed(path: infoPlistURL.path, underlying: error)
        }

        let plist: [String: Any]
        do {
            guard let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw ProjectPathResolutionError.infoPlistInvalidFormat(path: infoPlistURL.path)
            }
            plist = parsed
        } catch {
            throw ProjectPathResolutionError.infoPlistParseFailed(path: infoPlistURL.path, underlying: error)
        }

        guard let workspacePath = plist["WorkspacePath"] as? String else {
            throw ProjectPathResolutionError.workspacePathMissing(path: infoPlistURL.path)
        }

        let workspaceURL = URL(fileURLWithPath: workspacePath)

        // WorkspacePath points to .xcworkspace or .xcodeproj - we want the containing directory
        if workspacePath.hasSuffix(".xcworkspace") || workspacePath.hasSuffix(".xcodeproj") {
            return workspaceURL.deletingLastPathComponent()
        }

        return workspaceURL
    }
}

enum ProjectPathResolutionError: Error, LocalizedError {
    case noValidPathFound(cwd: String, reason: String)
    case derivedDataPathInvalid(path: String)
    case infoPlistNotFound(path: String)
    case infoPlistReadFailed(path: String, underlying: Error)
    case infoPlistParseFailed(path: String, underlying: Error)
    case infoPlistInvalidFormat(path: String)
    case workspacePathMissing(path: String)

    var errorDescription: String? {
        switch self {
        case .noValidPathFound(let cwd, let reason):
            return """
                Unable to determine project root.

                Current working directory: \(cwd)
                Reason: \(reason)

                Expected one of:
                  - Running from Xcode (DerivedData with info.plist)
                  - Current directory is the project root (contains cdk/ and Package.swift)
                  - Current directory is inside the project tree

                Suggestion: Run this app from Xcode or from within the project directory
                """

        case .derivedDataPathInvalid(let path):
            return "DerivedData path structure is invalid: \(path)"

        case .infoPlistNotFound(let path):
            return "info.plist not found at expected location: \(path)"

        case .infoPlistReadFailed(let path, let underlying):
            return "Failed to read info.plist at \(path): \(underlying.localizedDescription)"

        case .infoPlistParseFailed(let path, let underlying):
            return "Failed to parse info.plist at \(path): \(underlying.localizedDescription)"

        case .infoPlistInvalidFormat(let path):
            return "info.plist at \(path) is not a valid dictionary format"

        case .workspacePathMissing(let path):
            return "info.plist at \(path) does not contain WorkspacePath key"
        }
    }
}
