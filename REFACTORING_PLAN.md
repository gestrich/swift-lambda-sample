# MacAppModel Refactoring Plan

## Overview

The `MacAppModel` currently acts as an intermediary between views and services (Remote, XcodeLocal, LinuxLocal). This abstraction adds unnecessary complexity because:

1. Services themselves are already `@Observable` - no need for an intermediate model to relay state
2. The abstraction via `ConnectionMode` enum tries to unify services that have fundamentally different capabilities
3. Views can connect directly to services without losing functionality

## Goal

Eliminate most of `MacAppModel` by having views connect directly to their respective services. The model will eventually only coordinate local service selection (Xcode vs Linux), not act as a proxy for all service operations.

---

## Phase 1: Decouple Remote View from MacAppModel (COMPLETED)

**Goal**: The remote service view should connect directly to `RemoteService` with no `MacAppModel` involvement.

### Tasks

- [x] **1.1** Create `RemoteServiceView.swift` - a new view that takes `RemoteService` directly (not via MacAppModel)
  - Contains the CDK Infrastructure section
  - Contains the GitHub CI section
  - Has its own endpoint display/status section

- [x] **1.2** Update `DeployView` to conditionally render `RemoteServiceView` when in remote mode
  - Pass `model.remoteService` directly to the new view
  - Removed remote-specific sections from `DeployView` (cdkInfrastructureSection, githubCISection)

- [x] **1.3** Remove remote-related properties from `MacAppModel`
  - Removed `githubService` property (accessed via RemoteService directly)
  - Removed `cdkInfrastructureService` property (accessed via RemoteService directly)

- [x] **1.4** Build verification - all targets compile successfully

### Deferred to Phase 2

- [ ] **1.4** Remove remote case handling from `ConnectionMode` enum (requires more restructuring)
- [ ] **1.5** Update `ContentView` to handle remote mode separately (requires more restructuring)

---

## Phase 2: Rename MacAppModel to LocalServiceModel

**Goal**: Clarify that the model is only for coordinating local services.

### Tasks

- [ ] **2.1** Rename `MacAppModel` to `LocalServiceModel`
  - Update all file references
  - Update environment key usage

- [ ] **2.2** Rename `ConnectionMode` to `LocalServiceMode`
  - Only contains `.localXcode(XcodeLocalService)` and `.localLinux(LinuxLocalService)`

- [ ] **2.3** Update `DeployView` to use the new naming
  - Mode picker should only show Xcode/Linux options when using LocalServiceModel

- [ ] **2.4** Create top-level navigation between Remote and Local
  - Could be tabs or a different picker
  - Remote tab shows RemoteServiceView (no LocalServiceModel involved)
  - Local tab shows LocalServiceView with mode picker (Xcode/Linux)

---

## Phase 3: Simplify LocalServiceModel Further

**Goal**: Since XcodeLocalService and LinuxLocalService are so similar, evaluate if LocalServiceModel is even needed.

### Tasks

- [ ] **3.1** Evaluate if LocalServiceModel can be eliminated entirely
  - Both local services conform to same protocols
  - Views could take a `any LambdaService & LocalBuildProvider & LocalLambdaProvider` directly

- [ ] **3.2** If keeping LocalServiceModel, simplify it
  - Remove LambdaService conformance (views query services directly)
  - Keep only: mode selection, service lifecycle coordination, persistence

- [ ] **3.3** Consider using SwiftUI @Environment for service injection
  - Each service type could have its own environment key
  - Views declare which services they need

---

## Architecture After Refactoring

```
ContentView
├── RemoteTab
│   └── RemoteServiceView (uses RemoteService directly)
│       ├── CDKInfrastructureSectionView
│       ├── GitHubCISectionView
│       ├── EndpointSection
│       └── OutputSection
│
└── LocalTab
    └── LocalServiceView (uses LocalServiceModel for Xcode/Linux selection)
        ├── ModePicker (Xcode / Linux)
        ├── DockerServicesSection
        ├── BuildSection
        ├── LambdaSection
        └── OutputSection
```

## Benefits

1. **Clearer ownership**: Each view knows exactly which service it depends on
2. **No proxy overhead**: No intermediate model relaying observable state
3. **Better separation**: Remote and Local have different capabilities, shouldn't share abstraction
4. **Simpler testing**: Views can be tested with mock services directly
5. **Reduced code**: Remove ~200 lines of forwarding code in MacAppModel/ConnectionMode

## Notes

- Services are already `@Observable` - SwiftUI will react to their changes directly
- The `LambdaService` protocol is still useful for shared capabilities (endpoint, status, testing)
- Local-only protocols (`LocalBuildProvider`, `LocalLambdaProvider`, `LocalDockerServicesProvider`) correctly capture local-specific functionality
