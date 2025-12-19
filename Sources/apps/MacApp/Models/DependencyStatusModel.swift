import CLISDK
import SetupFeature
import Foundation
import Observation

/// Observable model for dependency installation status.
/// Uses workflows from service-setup to check and install dependencies.
@MainActor
@Observable
public final class DependencyStatusModel {
    // MARK: - State

    public enum ModelState: Sendable {
        case uninitialized
        case checking(prior: DependencySnapshot?)
        case ready(DependencySnapshot)
        case installing(CLITool, prior: DependencySnapshot?)
    }

    public private(set) var state: ModelState = .uninitialized

    // MARK: - Dependencies

    public let cliClient: CLIClient
    private let statusWorkflow: DependencyStatusWorkflow
    private let installWorkflow: DependencyInstallWorkflow

    // MARK: - Init

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
        self.statusWorkflow = DependencyStatusWorkflow(cliClient: cliClient)
        self.installWorkflow = DependencyInstallWorkflow(cliClient: cliClient)
        Task { await checkAll() }
    }

    // MARK: - Public API

    /// Check all dependency statuses
    public func checkAll() async {
        let prior = state.snapshot
        state = .checking(prior: prior)

        do {
            for try await state in statusWorkflow.stream(options: .all) {
                if case .complete = state.step,
                   case .snapshot(let snapshot) = state.detail {
                    self.state = .ready(snapshot)
                }
            }
        } catch {
            if let prior {
                state = .ready(prior)
            } else {
                state = .uninitialized
            }
        }
    }

    /// Install a specific dependency
    public func install(_ tool: CLITool) async {
        let prior = state.snapshot
        state = .installing(tool, prior: prior)

        do {
            let options = DependencyInstallWorkflow.Options(tool: tool)
            for try await state in installWorkflow.stream(options: options) {
                if case .complete = state.step {
                    await checkAll()
                    return
                }
            }
        } catch {
            if let prior {
                state = .ready(prior)
            } else {
                state = .uninitialized
            }
        }
    }

    // MARK: - Convenience Accessors

    /// Get status for a specific tool
    public func status(for tool: CLITool) -> CLIToolStatus? {
        state.snapshot?.status(for: tool)
    }

    /// Whether we're currently checking dependencies
    public var isChecking: Bool {
        if case .checking = state { return true }
        return false
    }

    /// Check if we're currently installing a specific tool
    public func isInstalling(_ tool: CLITool) -> Bool {
        if case .installing(let t, _) = state { return t == tool }
        return false
    }

    // MARK: - Backward-Compatible Properties

    /// Homebrew installation status (backward-compatible)
    public var homebrewStatus: DependencyUIState {
        uiState(for: .homebrew)
    }

    /// Node.js installation status (backward-compatible)
    public var nodejsStatus: DependencyUIState {
        uiState(for: .nodejs)
    }

    /// Docker installation status (backward-compatible)
    public var dockerStatus: DependencyUIState {
        uiState(for: .docker)
    }

    /// AWS CLI installation status (backward-compatible)
    public var awsCLIStatus: DependencyUIState {
        uiState(for: .awsCLI)
    }

    /// CDK installation status (backward-compatible)
    public var cdkStatus: DependencyUIState {
        uiState(for: .cdk)
    }

    /// GitHub CLI installation status (backward-compatible)
    public var githubCLIStatus: DependencyUIState {
        uiState(for: .githubCLI)
    }

    /// Convert CLIToolStatus to DependencyUIState for backward compatibility
    private func uiState(for tool: CLITool) -> DependencyUIState {
        if case .checking = state {
            return .checking
        }
        if case .installing(let t, _) = state, t == tool {
            return .checking
        }

        guard let status = state.snapshot?.status(for: tool) else {
            return .unknown
        }

        return status.isInstalled ? .installed : .notInstalled
    }

    // MARK: - Single Tool Check

    /// Check a specific tool's installation status
    public func check(_ tool: CLITool) async {
        await checkSingleTool(tool)
    }

    // MARK: - Backward-Compatible Methods

    /// Check Homebrew installation status
    public func checkHomebrew() async {
        await checkSingleTool(.homebrew)
    }

    /// Check Node.js installation status
    public func checkNodeJS() async {
        await checkSingleTool(.nodejs)
    }

    /// Check Docker installation status
    public func checkDocker() async {
        await checkSingleTool(.docker)
    }

    /// Check AWS CLI installation status
    public func checkAWSCLI() async {
        await checkSingleTool(.awsCLI)
    }

    /// Check CDK installation status
    public func checkCDK() async {
        await checkSingleTool(.cdk)
    }

    /// Check GitHub CLI installation status
    public func checkGitHubCLI() async {
        await checkSingleTool(.githubCLI)
    }

    /// Check a single tool and merge results into current snapshot
    private func checkSingleTool(_ tool: CLITool) async {
        let prior = state.snapshot
        state = .checking(prior: prior)

        do {
            let options = DependencyStatusWorkflow.Options(tools: [tool])
            for try await workflowState in statusWorkflow.stream(options: options) {
                if case .complete = workflowState.step,
                   case .snapshot(let newSnapshot) = workflowState.detail {
                    var statuses = prior?.statuses ?? [:]
                    for (key, value) in newSnapshot.statuses {
                        statuses[key] = value
                    }
                    state = .ready(DependencySnapshot(statuses: statuses))
                }
            }
        } catch {
            if let prior {
                state = .ready(prior)
            } else {
                state = .uninitialized
            }
        }
    }
}

// MARK: - ModelState Extension

extension DependencyStatusModel.ModelState {
    var snapshot: DependencySnapshot? {
        switch self {
        case .uninitialized:
            return nil
        case .checking(let prior):
            return prior
        case .ready(let snapshot):
            return snapshot
        case .installing(_, let prior):
            return prior
        }
    }
}

/// UI state for dependency status (app-layer concern)
public enum DependencyUIState: Equatable, Sendable {
    case unknown
    case checking
    case installed
    case notInstalled

    public var isInstalled: Bool {
        self == .installed
    }

    public var isChecking: Bool {
        self == .checking
    }
}
