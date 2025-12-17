import Foundation

public enum BuildError: Error, LocalizedError {
    case failed(exitCode: Int32)

    public var errorDescription: String? {
        switch self {
        case .failed(let exitCode):
            return "Build failed with exit code \(exitCode)"
        }
    }
}
