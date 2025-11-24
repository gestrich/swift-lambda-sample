# Lambda Container Service Refactoring Summary

## Date: November 23-24, 2025

## Overview

Refactored `LocalDevelopmentService` to extract service management into dedicated classes, reducing file size by 28% and improving code organization. Created a single-command workflow for running Lambda containers locally with all dependencies.

---

## What Was Done

### 1. Service Extraction

**Created three new service classes:**

#### PostgreSQLService.swift (103 lines)
- Manages PostgreSQL Docker container lifecycle
- Provides connection information via `PostgreSQLConnectionInfo` struct
- Methods: `start()`, `stop()`, `isRunning()`
- Configuration: postgres-lambda image, port 5432, docker/docker credentials

#### MinIOService.swift (174 lines)
- Manages MinIO S3 Docker container lifecycle
- Provides credentials via `MinIOCredentials` struct
- Methods: `start()`, `stop()`, `createBucket()`, `isRunning()`
- Configuration: quay.io/minio/minio image, ports 9000 (S3) + 9001 (console)
- Fixed: Permission issues by preserving data directory instead of recreating

#### LambdaContainerService.swift (273 lines)
- Manages Lambda Docker container lifecycle
- Uses `LambdaContainerConfig` for configuration
- Methods: `runInteractive()`, `startDetached()`, `stop()`, `waitForReady()`, `setupNetwork()`
- Manages Docker network setup and service connections
- Provides environment variables for containerized Lambda

### 2. LocalDevelopmentService Reduction

**Before:** 709 lines
**After:** 437 lines
**Reduction:** 272 lines (38%)

Now acts as orchestrator, delegating to specialized services.

### 3. Single-Command Workflow

#### Start Everything:
```bash
./tools.sh local lambda run-container
```

**What it does automatically:**
1. Stops any existing Lambda container
2. Starts PostgreSQL service
3. Starts MinIO S3 service
4. Sets up Docker network (lambda-local)
5. Connects services to network
6. Starts Lambda container in **detached mode** (background)

#### Stop Everything:
```bash
./tools.sh local lambda stop
```

**What it does:**
1. Stops Lambda container
2. Stops PostgreSQL service
3. Stops MinIO S3 service

### 4. Fixes Applied

**MinIO Permission Issues:**
- Problem: Removing data directory on each start destroyed MinIO's internal `.minio.sys` structure
- Solution: Only create data directory if it doesn't exist, preserve MinIO's internal files
- Result: MinIO runs successfully without file access errors

**TTY Issues:**
- Problem: Interactive Docker containers (`-it`) don't work through Swift's Process API
- Solution: Use detached mode (`-d`) instead, Lambda runs in background
- Result: Container starts successfully without "interrupted system call" errors

---

## Testing Results

All endpoints tested successfully using proper API Gateway request format:

### S3 Endpoints ✅
- **Upload file:** POST /api/files → "File uploaded: test.txt"
- **List files:** GET /api/files → ["test.txt"]
- **Download file:** GET /api/files/test.txt → base64 data

### PostgreSQL Endpoints ✅
- **Initialize database:** POST /api/database → "Database Initialized"
- **Create user:** POST /api/users → User created with UUID
- **List users:** GET /api/users → Array of users

### Container Status ✅
```
lambda-test-container: Up (Port 8080)
postgres-lambda: Up (Port 5432)
minio-lambda: Up (Ports 9000, 9001)
```

---

## File Structure

```
Sources/SwiftDeploy/
├── Services/
│   ├── PostgreSQLService.swift       [NEW - 103 lines]
│   ├── MinIOService.swift             [NEW - 174 lines]
│   ├── LambdaContainerService.swift   [NEW - 273 lines]
│   ├── DockerService.swift            [EXISTING]
│   └── CLIService.swift               [EXISTING]
├── LocalDevelopmentService.swift      [MODIFIED - 437 lines, was 709]
└── ...

Sources/SwiftDeployCLI/Commands/
└── LocalCommand.swift                 [MODIFIED]
```

---

## Benefits

✅ **Separation of Concerns** - Each service manages its own Docker container
✅ **Reduced Complexity** - Main service file 38% smaller
✅ **Reusability** - Services can be used independently
✅ **Testability** - Easier to unit test individual services
✅ **Maintainability** - Changes to one service don't affect others
✅ **Single Command** - One command starts everything, one command stops everything

---

## Commits Made

1. `c04b99c` - Extract PostgreSQL and MinIO services into separate files
2. `847aa12` - Extract Lambda container management into LambdaContainerService
3. `30367f3` - Make run-container do complete setup and add shutdown command
4. `5c92fb6` - Fix: Print Docker command instead of trying to run interactively
5. `22d7f95` - Fix: Run Lambda container in detached mode, not interactively
6. `b25a746` - Fix MinIO permission issues by not removing data directory

---

## Next Planned Work

### MacApp Integration

The MacApp needs to be updated to use the same local development infrastructure:

#### 1. Start Container from MacApp
- **Goal:** MacApp can start Lambda container in background
- **Implementation:** Call `LocalDevelopmentService.runLambdaContainer()` from MacApp UI
- **UI:** Add "Start Local Lambda" button in MacApp
- **Same code path as CLI** - Reuse existing service classes

#### 2. Connect MacApp Client to Container
- **Goal:** MacApp's API client can communicate with local Lambda container
- **Implementation:**
  - Add "Local Container" mode to MacApp settings
  - Configure `APIClient` with `http://localhost:8080` endpoint
  - Use local Lambda endpoint instead of AWS API Gateway
- **Benefit:** Test Lambda locally without deploying to AWS

#### 3. Auto-Create S3 Bucket on Startup
- **Current Issue:** Bucket must be created manually after container starts
- **Fix Needed:** Add bucket creation to `runLambdaContainer()` workflow
- **Implementation:**
  ```swift
  // In LocalDevelopmentService.runLambdaContainer():
  // After starting services, before starting Lambda:
  try await minioService.createBucket(bucketName: "org.gestrich.sandbox")
  ```
- **Result:** Bucket exists automatically, S3 endpoints work immediately

#### 4. Stop Container from MacApp
- **Goal:** MacApp can stop Lambda container and services
- **Implementation:** Call `LocalDevelopmentService.stopLambdaContainerAndServices()` from MacApp UI
- **UI:** Add "Stop Local Lambda" button in MacApp
- **Same code path as CLI** - Reuse existing shutdown method

### Implementation Plan

**Phase 1: Service Access**
- Make `LocalDevelopmentService` accessible from MacApp
- Already available in SwiftDeploy module, just needs to be imported

**Phase 2: UI Controls**
- Add "Local Lambda" section to MacApp settings/toolbar
- Add Start/Stop buttons
- Show container status (running/stopped)

**Phase 3: API Client Configuration**
- Add local endpoint option to `APIConfiguration`
- Switch between AWS API Gateway and local container
- Update `APIClient` to handle local mode

**Phase 4: Automatic Bucket Creation**
- Add `createBucket()` call to startup workflow
- Handle bucket already exists error gracefully
- Verify bucket exists before starting Lambda

**Phase 5: Testing**
- Test MacApp can start/stop container
- Test MacApp can connect to local Lambda
- Test all CRUD operations work locally
- Test switching between local and AWS modes

---

## Current State

**Working:** ✅
- CLI commands (`./tools.sh local lambda run-container` and `stop`)
- PostgreSQL service (start/stop)
- MinIO service (start/stop, bucket creation)
- Lambda container (detached mode)
- All API endpoints (S3, PostgreSQL, users)
- Docker networking (lambda-local)

**Needs Work:**
- Auto-create S3 bucket on container startup
- MacApp integration (planned next)

---

## Technical Notes

### Docker Network
- Name: `lambda-local`
- Containers: postgres-lambda, minio-lambda, lambda-test-container
- DNS resolution works between containers (e.g., `http://minio-lambda:9000`)

### Environment Variables
All set automatically by `LambdaContainerService.getEnvironmentVariables()`:
- PostgreSQL: `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER_NAME`, `POSTGRES_PASSWORD`, `POSTGRES_DBNAME`
- MinIO: `AWS_ENDPOINT_URL`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `S3_BUCKET_NAME`
- Lambda: `LOCAL_LAMBDA_SERVER_ENABLED`, `LOCAL_LAMBDA_HOST`

### API Gateway Request Format
Local Lambda expects full API Gateway event structure:
```json
{
  "resource": "/api/users",
  "path": "/api/users",
  "httpMethod": "GET",
  "requestContext": {...},
  "body": null,
  "isBase64Encoded": false
}
```

---

## References

- Main refactoring in: `Sources/SwiftDeploy/LocalDevelopmentService.swift`
- Service classes in: `Sources/SwiftDeploy/Services/`
- CLI commands in: `Sources/SwiftDeployCLI/Commands/LocalCommand.swift`
- Test reference: `Tests/SwiftDeployTests/LinuxDeployTests.swift`
