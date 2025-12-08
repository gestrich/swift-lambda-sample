# Integration Tests

This directory contains integration tests for the Swift Lambda Sample project.

## XcodeLocalIntegrationTests

### Overview

The `XcodeLocalIntegrationTests` suite provides end-to-end integration testing for the local development workflow. It validates that the entire local Lambda development environment works correctly, including Docker services, Lambda execution, and API endpoints.

### What It Tests

The test suite performs the following steps:

1. **Environment Setup**
   - Copies the local configuration file to `~/.swiftSampleDemo/swiftLambdaDemo.json`

2. **Service Startup**
   - Starts PostgreSQL container (`postgres_lambda`)
   - Starts MinIO S3-compatible container (`minio_lambda`)
   - Verifies both containers are running

3. **Lambda Execution**
   - Starts the Swift Lambda in local server mode on port 8080
   - Waits for the Lambda to be ready (up to 30 seconds)

4. **S3 Integration Test**
   - Posts to `/api/file` endpoint
   - Validates S3 file upload and download operations
   - Expects response: `"File uploaded and downloaded"`

5. **PostgreSQL Integration Test**
   - Posts to `/api/database` endpoint
   - Validates database initialization and table creation
   - Expects response: `"Database Initialized"`

6. **Cleanup**
   - Stops the Lambda process
   - Stops and removes Docker containers

### Running the Tests

```bash
# Run all integration tests
swift test --filter XcodeLocalIntegrationTests

# Run with verbose output
swift test --filter XcodeLocalIntegrationTests --verbose

# Run a specific test
swift test --filter testLocalDevelopmentWorkflow
```

### Prerequisites

Before running the tests, ensure you have:

1. **Docker Desktop** installed and running
2. **Swift 6.2+** installed
3. **Configuration file** exists: `swiftLambdaDemo.json` in the project root

### Test Duration

The integration test typically takes **2-5 minutes** to complete:
- **~30-60 seconds**: Building Swift Lambda executable
- **~3-5 seconds**: Starting Docker containers
- **~30-60 seconds**: Compiling and starting Lambda server
- **~2-3 seconds**: Running API tests
- **~2-3 seconds**: Cleanup

### Troubleshooting

#### Test Fails: "PostgreSQL container should be running"

**Issue**: PostgreSQL container failed to start

**Solution**:
```bash
# Check Docker is running
docker ps

# Manually start services to see errors
./tools.sh local-start-all

# Check PostgreSQL logs
docker logs postgres_lambda
```

#### Test Fails: "Lambda failed to start within 30 seconds"

**Issue**: Lambda compilation or startup took too long

**Solution**:
- Try running manually via swift run:
  ```bash
  LOCAL_LAMBDA_SERVER_ENABLED=true \
  MOCK_AWS_CREDENTIALS=true \
  LOCAL_LAMBDA_PORT=8080 \
  swift run SwiftLambda
  ```

#### Test Fails: "S3 endpoint should return success message"

**Issue**: MinIO (S3) integration is not working

**Solution**:
```bash
# Check MinIO container
docker ps | grep minio_lambda

# Check MinIO logs
docker logs minio_lambda

# Verify configuration file
cat ~/.swiftSampleDemo/swiftLambdaDemo.json | jq '.s3'
```

#### Test Fails: "Database endpoint should return success message"

**Issue**: PostgreSQL connection or TLS issue

**Solution**:
```bash
# Test PostgreSQL connection
docker exec -e PGPASSWORD=docker postgres_lambda \
  psql -U docker -h localhost -d docker -c "\l"

# Check configuration
cat ~/.swiftSampleDemo/swiftLambdaDemo.json | jq '.postgres'
```

### Environment Variables

The test uses these environment variables when starting the Lambda:

- `LOCAL_LAMBDA_SERVER_ENABLED=true` - Enables local HTTP server mode
- `MOCK_AWS_CREDENTIALS=true` - Uses mock AWS credentials
- `LOCAL_LAMBDA_PORT=8080` - Port for the local Lambda server

### Test Architecture

The test uses the `tools.sh` bash script to manage the lifecycle:

```swift
// Start services
./tools.sh local-start-all

// Run Lambda
swift run SwiftLambda

// Test endpoints
./tools.sh local-test 8080

// Cleanup
./tools.sh local-stop-all
```

### CI/CD Integration

This test can be run in CI/CD pipelines that support Docker:

```yaml
# GitHub Actions example
- name: Run Integration Tests
  run: swift test --filter XcodeLocalIntegrationTests
  env:
    DOCKER_HOST: unix:///var/run/docker.sock
```

**Note**: The test requires Docker to be available, so it won't work in environments without Docker support.

### Manual Verification

You can manually verify what the test does:

```bash
# 1. Start everything
./tools.sh local-copy-config
./tools.sh local-start-all

# 2. In one terminal, run Lambda
LOCAL_LAMBDA_SERVER_ENABLED=true \
MOCK_AWS_CREDENTIALS=true \
LOCAL_LAMBDA_PORT=8080 \
swift run SwiftLambda

# 3. In another terminal, test S3 endpoint
curl -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d @test-api-gateway-event.json

# 4. Test database endpoint
curl -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d '{
    "resource": "/api/database",
    "path": "/api/database",
    "httpMethod": "POST",
    "headers": {},
    "requestContext": {
      "resourceId": "test",
      "apiId": "test",
      "httpMethod": "POST",
      "path": "/api/database"
    }
  }'

# 5. Cleanup (stop Lambda with Ctrl+C, then)
./tools.sh local-stop-all
```

### Contributing

When modifying the integration tests:

1. Ensure tests are **idempotent** - can run multiple times
2. Clean up all resources in the test teardown
3. Add appropriate error messages for debugging
4. Update this README if adding new test cases
