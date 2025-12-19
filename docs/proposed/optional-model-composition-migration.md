# Optional Model Composition Migration

**Date:** 2024-12-19
**Status:** Proposed
**Related:** [layered-architecture.md](../architecture/layered-architecture.md#model-composition)

## Objective

Migrate MacApp to use optional model composition pattern consistently. Models that depend on configuration should be nil when configuration is missing, rather than existing in an unconfigured state.

## Background

The Model Composition pattern documented in `layered-architecture.md` establishes that configuration-dependent models should be optional. Currently, MacApp has inconsistent application of this pattern:

**Already Optional:**
- `DeployRemoteModel` — nil if AWS config missing

**Should Be Optional (but aren't):**
- `GitHubCIModel` — depends on GitHub config
- `CloudWatchLogsModel` — depends on AWS config
- `DependencyStatusModel` — created eagerly, checks immediately

**Could Be Lazy:**
- `DeployLinuxModel` — only needed if user selects Linux mode

## Current State

```
AppModel
├── remoteModel: DeployRemoteModel?     ✓ Already optional
├── remoteServiceError: Error?          ✓ Captures init failure
├── xcodeLocalService: DeployXcodeModel     (always created)
├── linuxLocalService: DeployLinuxModel     (always created - could be lazy)
├── dependencyStatusModel: DependencyStatusModel  (always created - starts work immediately)
├── xcodeLocalModel: LocalServicesModel     (wrapper)
└── linuxLocalModel: LocalServicesModel     (wrapper)

RemoteServiceView (creates in .task)
├── githubCIModel: GitHubCIModel?       ✓ Already optional
├── cloudWatchLogsModel: CloudWatchLogsModel  (should be optional)
└── lambdaBuildService: LambdaBuildService    (should be optional)
```

## Target State

```
AppModel
├── remoteModel: DeployRemoteModel?     (optional - AWS config)
├── githubModel: GitHubCIModel?         (optional - GitHub config) ← MOVE HERE
├── xcodeLocalService: DeployXcodeModel (always created)
├── linuxLocalService: DeployLinuxModel? (optional - lazy on mode switch)
└── dependencyStatusModel: DependencyStatusModel? (optional - lazy on navigation)

DeployRemoteModel
├── cloudWatchLogsModel: CloudWatchLogsModel  (always available - parent requires AWS)
└── lambdaBuildService: LambdaBuildService    (always available - parent requires AWS)
```

## Migration Phases

### [ ] Phase 1: Move GitHubCIModel to AppModel

Currently created in `RemoteServiceView.task`. Move to `AppModel` as optional property.

**Changes:**
- `AppModel`: Add `var githubModel: GitHubCIModel?`
- `AppModel.init`: Create if `GitHubConfiguration.loadConfig()` succeeds
- `AppModel`: Add `configureGitHub(_:)` and `clearGitHub()` methods
- `main.swift`: Add `.environment(appModel.githubModel)` injection
- `RemoteServiceView`: Remove `@State private var githubCIModel`
- `RemoteServiceView`: Use `@Environment(GitHubCIModel.self) private var githubModel: GitHubCIModel?`
- Views using GitHub: Update to receive via Environment

**Rationale:** GitHub config is app-level, not view-level. Model should persist across view lifecycle.

### [ ] Phase 2: Move CloudWatch/Lambda Models to DeployRemoteModel

These models depend on AWS config. Since `DeployRemoteModel` already requires AWS config, these should be non-optional children of that model.

**Changes:**
- `DeployRemoteModel`: Add `let cloudWatchLogsModel: CloudWatchLogsModel`
- `DeployRemoteModel`: Add `let lambdaBuildService: LambdaBuildService`
- `DeployRemoteModel.init`: Create these as part of initialization
- `RemoteServiceView`: Remove `@State` properties for these models
- `RemoteServiceView`: Access via `service.cloudWatchLogsModel`

**Rationale:** If DeployRemoteModel exists, AWS config exists, so these can always be created.

### [ ] Phase 3: Make DependencyStatusModel Lazy

Currently created in `AppModel.init` and immediately starts checking dependencies.

**Changes:**
- `AppModel`: Change to `var dependencyStatusModel: DependencyStatusModel?`
- `AppModel`: Add lazy creation method `func getDependencyStatusModel() -> DependencyStatusModel`
- Views: Create/access only when navigating to Setup view
- Consider: Move to `SetupView` as `@State` if only used there

**Rationale:** Dependency checking is only needed in Setup view, not at app startup.

### [ ] Phase 4: Make DeployLinuxModel Lazy (Optional)

Lower priority. Only create when user first switches to Linux mode.

**Changes:**
- `AppModel`: Change to `var linuxLocalService: DeployLinuxModel?`
- `AppModel`: Create on first access or mode switch to Linux
- Views: Handle optional appropriately

**Rationale:** Linux mode requires Docker. No need to initialize Docker clients until needed.

### [ ] Phase 5: Connect Settings View to Model Lifecycle

`SettingsView` already exists with AWS and GitHub configuration forms, but it only saves to disk — it doesn't notify `AppModel` to create/recreate models. Users must restart the app for config changes to take effect.

**Current state:**
- `SettingsView` saves config via `awsConfig.save()` and `githubConfig.save()`
- `onSave` callback calls `model.refreshStatus()` — only refreshes existing model
- No mechanism to create models when config becomes available

**Changes:**
- `SettingsView`: Inject `AppModel` via Environment
- `SettingsView.save()`: After saving config, call `appModel.reloadModels()`
- `AppModel`: Add `reloadModels()` that recreates optional models from disk config
- Alternative: Add specific methods like `appModel.reloadGitHubModel()`

## Environment Injection Strategy

After migration, environment injection at root:

```swift
// main.swift
WindowGroup {
    ContentView()
        .environment(appModel)
        .environment(appModel.remoteModel)
        .environment(appModel.githubModel)
        .environment(appModel.remoteModel?.cloudWatchLogsModel)
}
```

Views receive optional models:

```swift
struct GitHubSection: View {
    @Environment(GitHubCIModel.self) private var githubModel: GitHubCIModel?

    var body: some View {
        if let githubModel {
            GitHubCIView(model: githubModel)
        } else {
            ConfigureGitHubPrompt()
        }
    }
}
```

## Testing Considerations

- Test app launch without any configuration files
- Test app launch with only AWS config (no GitHub)
- Test app launch with only GitHub config (no AWS)
- Test configuration changes at runtime (Settings flow)
- Verify views update when models become available/unavailable
- Verify old models deallocate when replaced

## Success Criteria

- [ ] No models created for missing configuration
- [ ] Views show appropriate prompts when models unavailable
- [ ] Configuration changes in Settings immediately reflect in UI
- [ ] No eager work (dependency checking) at app startup
- [ ] Environment injection used consistently for model access
- [ ] All tests pass
