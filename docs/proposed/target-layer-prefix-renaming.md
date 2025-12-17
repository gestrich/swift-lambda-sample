# Target Layer Prefix Renaming

**Status**: Proposed
**Date**: 2024-12-17

## Objective

Rename all Swift package targets to use letter layer prefixes (`a-`, `b-`, `c-`, `d-`) so that alphabetical sorting matches architectural hierarchy.

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
| App | `a-` | Top layer, first alphabetically |
| Workflow | `b-` | Second layer |
| Service | `c-` | Third layer |
| SDK | `d-` | Bottom layer, last alphabetically |

The letter prefix indicates architectural depth (a = top, d = bottom).

## Target Rename Mapping

### Apps (`a-app-*`)

| Current | New |
|---------|-----|
| `app-cli` | `a-app-cli` |
| `app-lambda` | `a-app-lambda` |
| `app-mac` | `a-app-mac` |

### Workflows (`b-workflow-*`)

| Current | New |
|---------|-----|
| `workflows-deploy-remote` | `b-workflow-deploy-remote` |
| `workflows-setup` | `b-workflow-setup` |

### Services (`c-service-*`)

| Current | New |
|---------|-----|
| `service-deploy-core` | `c-service-deploy-core` |
| `service-deploy-local` | `c-service-deploy-local` |
| `service-deploy-remote` | `c-service-deploy-remote` |
| `service-lambda-build` | `c-service-lambda-build` |
| `service-setup` | `c-service-setup` |
| `service-storage` | `c-service-storage` |

### SDKs (`d-sdk-*`)

| Current | New |
|---------|-----|
| `sdk-aws` | `d-sdk-aws` |
| `sdk-cli` | `d-sdk-cli` |
| `sdk-cli-brew` | `d-sdk-cli-brew` |
| `sdk-cli-docker` | `d-sdk-cli-docker` |
| `sdk-cli-macros` | `d-sdk-cli-macros` |
| `sdk-cli-node` | `d-sdk-cli-node` |
| `sdk-client` | `d-sdk-client` |
| `sdk-github` | `d-sdk-github` |

### Tests

| Current | New |
|---------|-----|
| `sdk-cli-tests` | `d-sdk-cli-tests` |
| `service-deploy-remote-tests` | `c-service-deploy-remote-tests` |

## Resulting Alphabetical Order

After renaming, `ls Sources/` will show:

```
a-app-cli
a-app-lambda
a-app-mac
b-workflow-deploy-remote
b-workflow-setup
c-service-deploy-core
c-service-deploy-local
c-service-deploy-remote
c-service-lambda-build
c-service-setup
c-service-storage
d-sdk-aws
d-sdk-cli
d-sdk-cli-brew
d-sdk-cli-docker
d-sdk-cli-macros
d-sdk-cli-node
d-sdk-client
d-sdk-github
```

This order now reflects the architectural dependency hierarchy.

## Implementation Steps

### Phase 1: Rename SDK Targets (Bottom Layer First)

Rename from the bottom of the dependency graph up to avoid broken intermediate states.

1. Rename `Sources/sdk-*` directories to `Sources/d-sdk-*`
2. Update `Package.swift`:
   - Target names
   - Target dependencies (all `.target(name: "sdk-*")` → `.target(name: "d-sdk-*")`)
3. Update imports in source files (`import sdk_cli` → `import d_sdk_cli`)
4. Verify build: `swift build`

### Phase 2: Rename Service Targets

1. Rename `Sources/service-*` directories to `Sources/c-service-*`
2. Update `Package.swift` target names and dependencies
3. Update imports in source files
4. Verify build: `swift build`

### Phase 3: Rename Workflow Targets

1. Rename `Sources/workflows-*` directories to `Sources/b-workflow-*`
2. Update `Package.swift` target names and dependencies
3. Update imports in source files
4. Verify build: `swift build`

### Phase 4: Rename App Targets

1. Rename `Sources/app-*` directories to `Sources/a-app-*`
2. Update `Package.swift`:
   - Target names
   - Product names (keep `app-lambda` product name or rename to `a-app-lambda`)
3. Update imports in source files
4. Verify build: `swift build`

### Phase 5: Rename Test Targets

1. Rename `Tests/sdk-cli-tests` → `Tests/d-sdk-cli-tests`
2. Rename `Tests/service-deploy-remote-tests` → `Tests/c-service-deploy-remote-tests`
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
    name: "d-sdk-cli",
    dependencies: [
        .target(name: "d-sdk-cli-macros"),
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
import d_sdk_cli
import c_service_deploy_remote
import b_workflow_deploy_remote
```

## Considerations

### Product Name

The executable product `app-lambda` is referenced by:
- GitHub Actions workflow (`.github/workflows/deploy_dev.yml`)
- Build scripts (`build.sh`)
- AWS Lambda function name configuration

**Decision needed**: Keep product name as `app-lambda` or rename to `a-app-lambda`?

Recommendation: Keep product name as `app-lambda` for external compatibility:

```swift
.executable(
    name: "app-lambda",           // Keep external name
    targets: ["a-app-lambda"]     // Internal target renamed
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
    name: "d-sdk-cli-macros",
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
