# Target Layer Prefix Renaming

**Status**: Proposed
**Date**: 2024-12-17

## Objective

Rename all Swift package targets to use numbered layer prefixes (`a1-`, `a2-`, `a3-`, `a4-`) so that alphabetical sorting matches architectural hierarchy.

## Background

The project uses a four-layer architecture:

```
APP (top)      → Entry points, I/O
WORKFLOW       → Multi-step orchestration
SERVICE        → Models, configuration, stateful utilities
SDK (bottom)   → Stateless, reusable clients
```

Current target names sort alphabetically in a way that doesn't reflect this hierarchy:

```
app-cli          (A)
app-lambda       (A)
app-mac          (A)
sdk-aws          (S) ← SDK appears before service/workflow
sdk-cli          (S)
...
service-*        (S)
workflows-*      (W)
```

## Proposed Naming Convention

Add layer prefixes so alphabetical order matches top-to-bottom architecture:

| Layer | Prefix | Rationale |
|-------|--------|-----------|
| App | `a1-` | Top layer, first alphabetically |
| Workflow | `a2-` | Second layer |
| Service | `a3-` | Third layer |
| SDK | `a4-` | Bottom layer, last alphabetically |

The `a` prefix groups all architecture layers together; the number indicates depth.

## Target Rename Mapping

### Apps (`a1-app-*`)

| Current | New |
|---------|-----|
| `app-cli` | `a1-app-cli` |
| `app-lambda` | `a1-app-lambda` |
| `app-mac` | `a1-app-mac` |

### Workflows (`a2-workflow-*`)

| Current | New |
|---------|-----|
| `workflows-deploy-remote` | `a2-workflow-deploy-remote` |
| `workflows-setup` | `a2-workflow-setup` |

### Services (`a3-service-*`)

| Current | New |
|---------|-----|
| `service-deploy-core` | `a3-service-deploy-core` |
| `service-deploy-local` | `a3-service-deploy-local` |
| `service-deploy-remote` | `a3-service-deploy-remote` |
| `service-lambda-build` | `a3-service-lambda-build` |
| `service-setup` | `a3-service-setup` |
| `service-storage` | `a3-service-storage` |

### SDKs (`a4-sdk-*`)

| Current | New |
|---------|-----|
| `sdk-aws` | `a4-sdk-aws` |
| `sdk-cli` | `a4-sdk-cli` |
| `sdk-cli-brew` | `a4-sdk-cli-brew` |
| `sdk-cli-docker` | `a4-sdk-cli-docker` |
| `sdk-cli-macros` | `a4-sdk-cli-macros` |
| `sdk-cli-node` | `a4-sdk-cli-node` |
| `sdk-client` | `a4-sdk-client` |
| `sdk-github` | `a4-sdk-github` |

### Tests

| Current | New |
|---------|-----|
| `sdk-cli-tests` | `a4-sdk-cli-tests` |
| `service-deploy-remote-tests` | `a3-service-deploy-remote-tests` |

## Resulting Alphabetical Order

After renaming, `ls Sources/` will show:

```
a1-app-cli
a1-app-lambda
a1-app-mac
a2-workflow-deploy-remote
a2-workflow-setup
a3-service-deploy-core
a3-service-deploy-local
a3-service-deploy-remote
a3-service-lambda-build
a3-service-setup
a3-service-storage
a4-sdk-aws
a4-sdk-cli
a4-sdk-cli-brew
a4-sdk-cli-docker
a4-sdk-cli-macros
a4-sdk-cli-node
a4-sdk-client
a4-sdk-github
```

This order now reflects the architectural dependency hierarchy.

## Implementation Steps

### Phase 1: Rename SDK Targets (Bottom Layer First)

Rename from the bottom of the dependency graph up to avoid broken intermediate states.

1. Rename `Sources/sdk-*` directories to `Sources/a4-sdk-*`
2. Update `Package.swift`:
   - Target names
   - Target dependencies (all `.target(name: "sdk-*")` → `.target(name: "a4-sdk-*")`)
3. Update imports in source files (`import sdk_cli` → `import a4_sdk_cli`)
4. Verify build: `swift build`

### Phase 2: Rename Service Targets

1. Rename `Sources/service-*` directories to `Sources/a3-service-*`
2. Update `Package.swift` target names and dependencies
3. Update imports in source files
4. Verify build: `swift build`

### Phase 3: Rename Workflow Targets

1. Rename `Sources/workflows-*` directories to `Sources/a2-workflow-*`
2. Update `Package.swift` target names and dependencies
3. Update imports in source files
4. Verify build: `swift build`

### Phase 4: Rename App Targets

1. Rename `Sources/app-*` directories to `Sources/a1-app-*`
2. Update `Package.swift`:
   - Target names
   - Product names (keep `app-lambda` product name or rename to `a1-app-lambda`)
3. Update imports in source files
4. Verify build: `swift build`

### Phase 5: Rename Test Targets

1. Rename `Tests/sdk-cli-tests` → `Tests/a4-sdk-cli-tests`
2. Rename `Tests/service-deploy-remote-tests` → `Tests/a3-service-deploy-remote-tests`
3. Update `Package.swift` test target names and dependencies
4. Run tests: `swift test`

### Phase 6: Update Documentation

1. Update `CLAUDE.md` source code structure section
2. Update `docs/architecture/layered-architecture.md` target naming section
3. Update any other docs referencing target names

## Files to Modify

### Package.swift Changes

Every target definition and dependency reference:

```swift
// Before
.target(
    name: "sdk-cli",
    dependencies: [
        .target(name: "sdk-cli-macros"),
    ]
)

// After
.target(
    name: "a4-sdk-cli",
    dependencies: [
        .target(name: "a4-sdk-cli-macros"),
    ]
)
```

### Import Statement Changes

Swift imports use underscores for hyphenated target names:

```swift
// Before
import sdk_cli
import service_deploy_remote
import workflows_deploy_remote

// After
import a4_sdk_cli
import a3_service_deploy_remote
import a2_workflow_deploy_remote
```

## Considerations

### Product Name

The executable product `app-lambda` is referenced by:
- GitHub Actions workflow (`.github/workflows/deploy_dev.yml`)
- Build scripts (`build.sh`)
- AWS Lambda function name configuration

**Decision needed**: Keep product name as `app-lambda` or rename to `a1-app-lambda`?

Recommendation: Keep product name as `app-lambda` for external compatibility:

```swift
.executable(
    name: "app-lambda",           // Keep external name
    targets: ["a1-app-lambda"]    // Internal target renamed
)
```

### String References to Target Names

Target names are referenced as strings in Swift code for building and deployment. These must also be updated:

| File | Reference | Purpose |
|------|-----------|---------|
| `Sources/service-deploy-local/LinuxLocalDevelopmentService.swift` | `"app-lambda"` | Build target for Linux container |
| `Sources/service-deploy-local/XcodeLocalDevelopmentService.swift` | `"app-lambda"` | Lambda product name constant |
| `Sources/service-deploy-remote/LambdaService/LambdaBuildService.swift` | `"app-lambda"` | Remote build target |
| `Sources/app-mac/Models/XcodeLocalModel.swift` | `"app-lambda"` | Executable path construction |
| `Sources/service-lambda-build/CLI/BuildScript.swift` | `"app-lambda"` | Documentation examples |
| `Sources/service-lambda-build/CLI/SwiftCLI.swift` | `"app-lambda"` | Documentation examples |

**External references** (may need to stay as `app-lambda` if product name is kept):
- `.github/workflows/deploy_dev.yml` - `productName: app-lambda`
- `build.sh` - Usage examples

**Recommendation**: If product name stays as `app-lambda`, the string references for building should also stay as `app-lambda` since they reference the product, not the target.

### Macro Target

The macro target `sdk-cli-macros` follows the same pattern:

```swift
.macro(
    name: "a4-sdk-cli-macros",
    ...
)
```

## Verification

After each phase:

1. `swift build` - Verify compilation
2. `swift test` - Verify tests pass
3. `swift run SwiftDeploy --help` - Verify CLI works

Final verification:
- `ls Sources/` shows correct alphabetical ordering
- All imports resolve correctly
- CI/CD pipeline succeeds

## Success Criteria

- [ ] All targets renamed with layer prefixes
- [ ] Alphabetical directory listing matches architectural hierarchy
- [ ] Build succeeds
- [ ] All tests pass
- [ ] Documentation updated
- [ ] CI/CD pipeline succeeds
