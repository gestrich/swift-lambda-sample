# Local Development Workflows Plan

## Overview

Create workflow targets for local development actions, used by both the Mac app (`a-app-mac`) and CLI app (`a-app-cli`).

## New Targets

### 1. `b-workflow-deploy-local-xcode`

Workflows for native macOS/Xcode development.

**Location:** `Sources/b-workflow-deploy-local-xcode/`
**Dependencies:** `c-service-deploy-local`, `d-sdk-cli`
**Service Type:** `XcodeLocalDevelopmentService` (concrete type)

### 2. `b-workflow-deploy-local-linux`

Workflows for Linux/Docker container development.

**Location:** `Sources/b-workflow-deploy-local-linux/`
**Dependencies:** `c-service-deploy-local`, `d-sdk-cli`
**Service Type:** `LinuxLocalDevelopmentService` (concrete type)

## Shared Types (in `c-service-deploy-local`)

Add to existing service target:

```swift
public enum LocalServiceType: Sendable, Hashable {
    case database
    case s3
    case dynamodb
}
```

## Workflow Pattern

Each workflow follows the established pattern:
- Struct conforming to `Sendable`
- `run()` method returning `AsyncThrowingStream<Progress, Error>`
- Nested `Progress` type with `step` and optional `detail`
- Nested `Options` type where configuration is needed
- Takes concrete service type (compile-time safety)

---

## Xcode Workflows (`b-workflow-deploy-local-xcode`)

### 1. XcodeBuildWorkflow

Build Lambda for native macOS development.

```swift
public struct XcodeBuildWorkflow: Sendable {
    private let service: XcodeLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case cleaning
            case building
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case buildPath(String)
        }
    }

    public struct Options: Sendable {
        public let clean: Bool
    }
}
```

### 2. XcodeStartLambdaWorkflow

Start the Lambda as native macOS process.

```swift
public struct XcodeStartLambdaWorkflow: Sendable {
    private let service: XcodeLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checkingBuild
            case starting
            case waitingForReady
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case port(Int)
        }
    }
}
```

### 3. XcodeStopLambdaWorkflow

Stop the Lambda process.

```swift
public struct XcodeStopLambdaWorkflow: Sendable {
    private let service: XcodeLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checking
            case stopping
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case wasRunning(Bool)
        }
    }
}
```

### 4. XcodeStartServicesWorkflow

Start local services for Xcode development.

```swift
public struct XcodeStartServicesWorkflow: Sendable {
    private let service: XcodeLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case startingDatabase
            case startingS3
            case creatingBucket
            case startingDynamoDB
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case serviceStarted(LocalServiceType)
        }
    }

    public struct Options: Sendable {
        public let services: Set<LocalServiceType>

        public static let all = Options(services: [.database, .s3, .dynamodb])
        public static func only(_ services: LocalServiceType...) -> Options {
            Options(services: Set(services))
        }
    }
}
```

### 5. XcodeStopServicesWorkflow

Stop local services for Xcode development.

```swift
public struct XcodeStopServicesWorkflow: Sendable {
    private let service: XcodeLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case stoppingDatabase
            case stoppingS3
            case stoppingDynamoDB
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case serviceStopped(LocalServiceType)
        }
    }

    public struct Options: Sendable {
        public let services: Set<LocalServiceType>

        public static let all = Options(services: [.database, .s3, .dynamodb])
    }
}
```

### 6. XcodeStartAllWorkflow

Start Lambda with all services for Xcode development.

```swift
public struct XcodeStartAllWorkflow: Sendable {
    private let service: XcodeLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case startingServices
            case startingLambda
            case waitingForReady
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case servicesProgress(XcodeStartServicesWorkflow.Progress)
            case lambdaProgress(XcodeStartLambdaWorkflow.Progress)
            case port(Int)
        }
    }
}
```

### 7. XcodeStopAllWorkflow

Stop Lambda and all services for Xcode development.

```swift
public struct XcodeStopAllWorkflow: Sendable {
    private let service: XcodeLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case stoppingLambda
            case stoppingServices
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case lambdaProgress(XcodeStopLambdaWorkflow.Progress)
            case servicesProgress(XcodeStopServicesWorkflow.Progress)
        }
    }
}
```

### 8. XcodeTestWorkflow

Test local Lambda endpoints (Xcode mode).

```swift
public struct XcodeTestWorkflow: Sendable {
    private let service: XcodeLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checkingLambda
            case testingFileUpload
            case testingFileList
            case testingFileDownload
            case testingDatabaseInit
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case testPassed(String)
            case testFailed(String, Error)
        }
    }
}
```

### 9. XcodeCopyConfigWorkflow

Copy configuration files to `~/.swiftSampleDemo/`.

```swift
public struct XcodeCopyConfigWorkflow: Sendable {
    private let service: XcodeLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case copying
            case complete
        }

        public enum Detail: Sendable {
            case copiedFile(String)
            case destinationPath(String)
        }
    }
}
```

---

## Linux Workflows (`b-workflow-deploy-local-linux`)

### 1. LinuxBuildWorkflow

Build Lambda for Linux/Docker container.

```swift
public struct LinuxBuildWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case cleaning
            case building
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case buildPath(String)
        }
    }

    public struct Options: Sendable {
        public let clean: Bool
    }
}
```

### 2. LinuxStartLambdaWorkflow

Start the Lambda as Docker container.

```swift
public struct LinuxStartLambdaWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checkingBuild
            case starting
            case waitingForReady
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case port(Int)
        }
    }
}
```

### 3. LinuxStopLambdaWorkflow

Stop the Lambda container.

```swift
public struct LinuxStopLambdaWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checking
            case stopping
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case wasRunning(Bool)
        }
    }
}
```

### 4. LinuxStartServicesWorkflow

Start local services for Linux development.

```swift
public struct LinuxStartServicesWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case startingDatabase
            case startingS3
            case creatingBucket
            case startingDynamoDB
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case serviceStarted(LocalServiceType)
        }
    }

    public struct Options: Sendable {
        public let services: Set<LocalServiceType>

        public static let all = Options(services: [.database, .s3, .dynamodb])
        public static func only(_ services: LocalServiceType...) -> Options {
            Options(services: Set(services))
        }
    }
}
```

### 5. LinuxStopServicesWorkflow

Stop local services for Linux development.

```swift
public struct LinuxStopServicesWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case stoppingDatabase
            case stoppingS3
            case stoppingDynamoDB
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case serviceStopped(LocalServiceType)
        }
    }

    public struct Options: Sendable {
        public let services: Set<LocalServiceType>

        public static let all = Options(services: [.database, .s3, .dynamodb])
    }
}
```

### 6. LinuxStartAllWorkflow

Start Lambda with all services for Linux development.

```swift
public struct LinuxStartAllWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case startingServices
            case setupNetwork
            case startingLambda
            case waitingForReady
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case servicesProgress(LinuxStartServicesWorkflow.Progress)
            case networkProgress(LinuxSetupNetworkWorkflow.Progress)
            case lambdaProgress(LinuxStartLambdaWorkflow.Progress)
            case port(Int)
        }
    }
}
```

### 7. LinuxStopAllWorkflow

Stop Lambda and all services for Linux development.

```swift
public struct LinuxStopAllWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case stoppingLambda
            case stoppingServices
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case lambdaProgress(LinuxStopLambdaWorkflow.Progress)
            case servicesProgress(LinuxStopServicesWorkflow.Progress)
        }
    }
}
```

### 8. LinuxTestWorkflow

Test local Lambda endpoints (Linux mode).

```swift
public struct LinuxTestWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checkingLambda
            case testingFileUpload
            case testingFileList
            case testingFileDownload
            case testingDatabaseInit
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case testPassed(String)
            case testFailed(String, Error)
        }
    }
}
```

### 9. LinuxCopyConfigWorkflow

Copy configuration files to `~/.swiftSampleDemo/`.

```swift
public struct LinuxCopyConfigWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case copying
            case complete
        }

        public enum Detail: Sendable {
            case copiedFile(String)
            case destinationPath(String)
        }
    }
}
```

### 10. LinuxSetupNetworkWorkflow (Linux-only)

Setup Docker network for container communication.

```swift
public struct LinuxSetupNetworkWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case creatingNetwork
            case connectingContainers
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case networkCreated(String)
            case containerConnected(String)
        }
    }
}
```

### 11. LinuxRunInteractiveWorkflow (Linux-only)

Run interactive container shell.

```swift
public struct LinuxRunInteractiveWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case preparing
            case launching
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case command(String)
        }
    }
}
```

---

## File Structure

```
Sources/b-workflow-deploy-local-xcode/
├── XcodeBuildWorkflow.swift
├── XcodeStartLambdaWorkflow.swift
├── XcodeStopLambdaWorkflow.swift
├── XcodeStartServicesWorkflow.swift
├── XcodeStopServicesWorkflow.swift
├── XcodeStartAllWorkflow.swift
├── XcodeStopAllWorkflow.swift
├── XcodeTestWorkflow.swift
└── XcodeCopyConfigWorkflow.swift

Sources/b-workflow-deploy-local-linux/
├── LinuxBuildWorkflow.swift
├── LinuxStartLambdaWorkflow.swift
├── LinuxStopLambdaWorkflow.swift
├── LinuxStartServicesWorkflow.swift
├── LinuxStopServicesWorkflow.swift
├── LinuxStartAllWorkflow.swift
├── LinuxStopAllWorkflow.swift
├── LinuxTestWorkflow.swift
├── LinuxCopyConfigWorkflow.swift
├── LinuxSetupNetworkWorkflow.swift
└── LinuxRunInteractiveWorkflow.swift
```

## Package.swift Updates

Add new targets:

```swift
.target(
    name: "b-workflow-deploy-local-xcode",
    dependencies: [
        "c-service-deploy-local",
        "d-sdk-cli",
    ]
),
.target(
    name: "b-workflow-deploy-local-linux",
    dependencies: [
        "c-service-deploy-local",
        "d-sdk-cli",
    ]
),
```

Update app targets to depend on the new workflow targets.

## Service Type Addition

Add to `c-service-deploy-local`:

**File:** `Sources/c-service-deploy-local/LocalServiceType.swift`

```swift
public enum LocalServiceType: Sendable, Hashable {
    case database
    case s3
    case dynamodb
}
```

## Implementation Order

1. ✅ Add `LocalServiceType` to `c-service-deploy-local`
2. ✅ Create `b-workflow-deploy-local-xcode` target and add to Package.swift
3. ✅ Create `b-workflow-deploy-local-linux` target and add to Package.swift
4. ✅ Implement Xcode workflows (simpler, no Docker networking)
5. ✅ Implement Linux workflows (includes Docker-specific workflows)

---

## Implementation Notes

### Phase 1: LocalServiceType and Workflow Targets (Completed)

**Date:** Phase completed

**What was implemented:**

1. **LocalServiceType enum** - Added to `c-service-deploy-local/LocalServiceType.swift`

2. **b-workflow-deploy-local-xcode target** - 9 workflows:
   - `XcodeBuildWorkflow` - Native macOS build
   - `XcodeStartLambdaWorkflow` - Start Lambda as native process
   - `XcodeStopLambdaWorkflow` - Stop Lambda process
   - `XcodeStartServicesWorkflow` - Start Docker services (PostgreSQL, MinIO, DynamoDB)
   - `XcodeStopServicesWorkflow` - Stop Docker services
   - `XcodeStartAllWorkflow` - Start services + Lambda
   - `XcodeStopAllWorkflow` - Stop Lambda + services
   - `XcodeTestWorkflow` - Test local endpoints
   - `XcodeCopyConfigWorkflow` - Copy config to ~/.swiftSampleDemo/

3. **b-workflow-deploy-local-linux target** - 11 workflows:
   - `LinuxBuildWorkflow` - Docker-based Linux build
   - `LinuxStartLambdaWorkflow` - Start Lambda container
   - `LinuxStopLambdaWorkflow` - Stop Lambda container
   - `LinuxStartServicesWorkflow` - Start Docker services
   - `LinuxStopServicesWorkflow` - Stop Docker services
   - `LinuxStartAllWorkflow` - Start services + network + Lambda
   - `LinuxStopAllWorkflow` - Stop Lambda + services
   - `LinuxTestWorkflow` - Test container endpoints
   - `LinuxCopyConfigWorkflow` - Copy config to ~/.swiftSampleDemo/
   - `LinuxSetupNetworkWorkflow` - Setup Docker network for container communication
   - `LinuxRunInteractiveWorkflow` - Run interactive container shell

**Technical Notes:**

- All workflows use `CLIOutputStream.makeStream()` to subscribe to CLI output
- Switch statements on `StreamOutput` must handle all cases: `.stdout`, `.stderr`, `.exit`, `.command`, `.error`
- Xcode workflows use port 8080 (native process)
- Linux workflows use port 8081 (Docker container) to avoid conflicts

### Next Steps

- Update `a-app-cli` to use the new workflow targets
- Update `a-app-mac` to use the new workflow targets
- Remove direct service calls from CLI commands in favor of workflows
