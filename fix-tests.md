# Fix Integration Tests - Plan & Background

## Current Status

**Test:** `LinuxContainerIntegrationTests`
**Status:** ❌ Failing with AWS credential errors
**Location:** `Tests/SwiftDeployTests/LinuxDeployTests.swift`

### Error Messages

```
InvalidAccessKeyId: The AWS Access Key Id you provided does not exist in our records.
UnrecognizedClient: The security token included in the request is invalid.
```

## Background

This integration test validates the full Lambda development workflow:
1. Start local services (PostgreSQL + MinIO)
2. Build Lambda for Linux
3. Run Lambda in Docker container
4. Test S3 and database endpoints
5. Clean up

### Previous Issues Resolved

1. ✅ **MinIO Region Configuration** - Fixed by using `MINIO_REGION_NAME` instead of `MINIO_REGION`
2. ✅ **Build Performance** - Added `swift run SwiftDeploy local build-lambda` to build once and reuse
3. ✅ **Code Duplication** - Refactored tests to use `LocalDevelopmentService` instead of custom implementations
4. ✅ **Configuration Management** - Moved all config (ports, container names, etc.) to `LocalDevelopmentService`

## Current Problem: AWS Credential Mismatch

### Root Cause

The Lambda container receives environment variables:
```bash
-e AWS_ACCESS_KEY_ID=admin
-e AWS_SECRET_ACCESS_KEY=password
-e AWS_REGION=us-east-1
-e AWS_ENDPOINT_URL=http://minio_lambda:9000
```

But MinIO is rejecting these credentials. Possible causes:
1. MinIO region not configured correctly on server side
2. MinIO data from previous runs with different config
3. Credential chain issues in Lambda runtime

### Changes Made to Fix

#### 1. Updated MinIO Region Configuration

**File:** `Sources/SwiftDeploy/LocalDevelopmentService.swift`

```swift
// OLD (wrong):
"MINIO_REGION": "us-east-1"

// NEW (correct for modern MinIO):
"MINIO_REGION_NAME": "us-east-1"
```

#### 2. Added Data Directory Cleanup

```swift
// Clean any existing MinIO data to avoid configuration conflicts
if FileManager.default.fileExists(atPath: minioDataPath) {
    print("→ Removing existing MinIO data...")
    try FileManager.default.removeItem(atPath: minioDataPath)
}
```

#### 3. Added Build Command

**Command:** `swift run SwiftDeploy local build-lambda`

**Benefits:**
- Build Lambda once (~7 minutes)
- Reuse the build for rapid testing iterations
- Test now skips build if Lambda already exists

**Implementation:**
```swift
// In LocalDevelopmentService
public func buildLambda(clean: Bool = false) async throws
public func isLambdaBuilt() -> Bool

// In test
let isBuilt = await localService.isLambdaBuilt()
if isBuilt {
    print("  ✅ Lambda already built, skipping build step")
} else {
    try await localService.buildLambda()
}
```

## Next Steps to Fix Credentials

### Hypothesis

MinIO might not be properly initialized with the region, or there's a timing issue where the Lambda starts before MinIO is fully configured.

### Debugging Plan

1. **Verify MinIO Environment Variables**
   ```bash
   docker inspect minio_lambda | jq '.[0].Config.Env'
   ```
   Should show `MINIO_REGION_NAME=us-east-1`

2. **Test MinIO Directly**
   ```bash
   docker run --rm --network lambda-local \
     -e AWS_ACCESS_KEY_ID=admin \
     -e AWS_SECRET_ACCESS_KEY=password \
     -e AWS_REGION=us-east-1 \
     amazon/aws-cli --endpoint-url http://minio_lambda:9000 \
     s3 ls
   ```
   Should list buckets without errors

3. **Check MinIO Logs**
   ```bash
   docker logs minio_lambda
   ```
   Look for region configuration messages

4. **Verify Lambda Environment**
   ```bash
   docker exec lambda-test-container env | grep AWS
   ```
   Verify all AWS environment variables are set correctly

### Potential Fixes

#### Option A: Wait for MinIO Initialization
Add a health check after starting MinIO:
```swift
// After starting MinIO, verify it's ready
try await waitForMinIOReady()
```

#### Option B: Use MinIO Client to Configure
```swift
// Configure MinIO region using mc admin
try await cliService.execute(
    command: "docker",
    arguments: [
        "exec", minioContainerName,
        "mc", "alias", "set", "local",
        "http://localhost:9000", "admin", "password"
    ]
)
```

#### Option C: Simplify Credentials
MinIO's default region is already `us-east-1`. Try removing explicit region configuration and see if it works with defaults.

## Test Workflow (Current)

### Build Lambda (Once)
```bash
swift run SwiftDeploy local build-lambda
```

### Run Tests (Fast Iteration)
```bash
swift test --filter LinuxContainerIntegrationTests
```

Expected output:
```
🚀 Step 1: Starting local services...
  → Removing existing MinIO data...
  ✅ MinIO started successfully
  ✅ PostgreSQL started successfully

🔧 Step 2: Setting up Docker network...
  ✅ Network setup complete!

📦 Creating S3 bucket in MinIO...
  ✅ S3 bucket 'org.gestrich.sandbox' created

🔨 Step 3: Checking Lambda build...
  ✅ Lambda already built, skipping build step  # <-- Fast!

🚀 Step 4: Starting Lambda in Linux container...
  ✅ Lambda container started
  ✅ Lambda is running and ready

🧪 Step 5: Testing S3 file upload/download...
  ✅ S3 test passed  # <-- Currently failing

🧪 Step 6: Testing PostgreSQL database initialization...
  ✅ Database test passed  # <-- Currently failing
```

## Files Changed

### Core Service
- `Sources/SwiftDeploy/LocalDevelopmentService.swift`
  - Added `buildLambda()` method
  - Added `isLambdaBuilt()` method
  - Updated MinIO region config: `MINIO_REGION_NAME`
  - Added MinIO data cleanup on start

### Commands
- `Sources/SwiftDeploy/Commands/LocalCommand.swift`
  - Added `BuildLambdaCommand`
  - New command: `swift run SwiftDeploy local build-lambda [--clean]`

### Tests
- `Tests/SwiftDeployTests/LinuxDeployTests.swift`
  - Refactored to use `LocalDevelopmentService` methods
  - Added build skip logic
  - Removed 163 lines of duplicate code
  - Added `inheritIO: true` to show build output

## Architecture Improvements

### Before
```
Test
├── Custom shell commands (Process())
├── Hardcoded configuration
├── Duplicate Docker logic
└── Always rebuilds Lambda (~7 min)
```

### After
```
Test
└── LocalDevelopmentService (reusable)
    ├── Centralized configuration
    ├── DockerService (type-safe)
    ├── CLIService (async/await)
    └── Build caching (skip if built)
```

## Commands Reference

### Local Development
```bash
# Build Lambda (once)
swift run SwiftDeploy local build-lambda

# Build Lambda (clean build)
swift run SwiftDeploy local build-lambda --clean

# Start services
swift run SwiftDeploy local start-services

# Stop services
swift run SwiftDeploy local stop-services

# Setup network
swift run SwiftDeploy local setup-network

# Run Lambda in container (interactive)
swift run SwiftDeploy local run-container

# Test Lambda endpoints
swift run SwiftDeploy local test
```

### Testing
```bash
# Run integration tests
swift test --filter LinuxContainerIntegrationTests

# Run all tests
swift test
```

## Next Actions

1. ✅ Build Lambda once: `swift run SwiftDeploy local build-lambda`
2. 🔍 Debug MinIO credentials with steps above
3. 🔧 Implement appropriate fix (Option A, B, or C)
4. ✅ Verify tests pass
5. 📝 Document successful configuration

## Success Criteria

- ✅ Tests pass without credential errors
- ✅ Build only happens once (cached for subsequent runs)
- ✅ Fast iteration cycle (< 1 minute per test run after initial build)
- ✅ Clean, maintainable code using service layer
- ✅ All configuration centralized in `LocalDevelopmentService`
