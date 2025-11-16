# Running Swift Lambda Locally with Xcode

This guide covers running and debugging the Swift Lambda function natively on your Mac using Xcode.

## When to Use This

- **Active development** - Fast iteration with Xcode debugging
- **Local testing** - Test Lambda logic without deploying to AWS
- **Debugging** - Use Xcode breakpoints and Swift tooling

## Prerequisites

- Xcode installed
- Docker Desktop installed and running ([Download](https://docs.docker.com/desktop/install/mac-install))

## Quick Start

### 1. Copy Configuration File

```bash
./tools.sh copyConfig
```

This creates `~/.swiftSampleDemo/swiftLambdaDemo.json` with local service configuration.

### 2. Start Local Services

```bash
./tools.sh startServices
```

This starts:
- **PostgreSQL** on `localhost:5432`
  - Username: `docker`
  - Password: `docker`
  - Database: `docker`
- **MinIO** (S3-compatible) on `localhost:9000`
  - Console: `localhost:9001`
  - Access Key: `admin`
  - Secret Key: `password`

Verify services are running:

```bash
docker ps
```

You should see:
- `postgres_lambda` - PostgreSQL database
- `minio_lambda` - MinIO S3 storage

### 3. Configure Xcode Environment Variables

Edit the scheme for the **SwiftLambda** target:

1. Product → Scheme → Edit Scheme
2. Select "Run" in the left sidebar
3. Click "Arguments" tab
4. Add these environment variables:

| Variable | Value | Description |
|----------|-------|-------------|
| `LOCAL_LAMBDA_SERVER_ENABLED` | `true` | Enables local HTTP server mode |
| `MOCK_AWS_CREDENTIALS` | `true` | Uses mock AWS credentials |
| `LOCAL_LAMBDA_PORT` | `8080` | Port for local Lambda server (avoids macOS port 7000 conflict) |

**Note**: Port 7000 is often occupied by macOS Control Center (AirPlay). We use port 8080 to avoid conflicts.

### 4. Run in Xcode

1. Select the **SwiftLambda** target
2. Select **My Mac** as the destination
3. Click the **Run** button (or press ⌘R)

The Lambda will start a local HTTP server on port 8080.

You should see in the Xcode console:
```
info LambdaRuntime: host="127.0.0.1" port=8080 [AWSLambdaRuntime] Server started and listening
```

### 5. Test the API

```bash
# Test S3 file upload/download (no database required)
curl -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d @test-api-gateway-event.json

# Expected response:
# {"headers":{"Content-Type":"application/json"},"body":"\"File uploaded and downloaded\"","statusCode":200}
```

**Note**: The local Lambda server uses the `/invoke` endpoint and expects API Gateway event payloads. See `test-api-gateway-event.json` for example format.

### 6. Stop Services

```bash
./tools.sh stopServices
```

## Testing Different Endpoints

### File Upload/Download (S3)

```bash
# Create test event
cat > test-file.json << 'EOF'
{
  "resource": "/api/file",
  "path": "/api/file",
  "httpMethod": "POST",
  "headers": {},
  "multiValueHeaders": {},
  "requestContext": {
    "resourceId": "test",
    "apiId": "test",
    "resourcePath": "/api/file",
    "httpMethod": "POST",
    "requestId": "test",
    "accountId": "123456789012",
    "stage": "local",
    "identity": {
      "sourceIp": "127.0.0.1"
    },
    "path": "/api/file"
  },
  "body": null,
  "isBase64Encoded": false
}
EOF

curl -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d @test-file.json
```

### Database Operations

```bash
# Initialize database
cat > test-database.json << 'EOF'
{
  "resource": "/api/database",
  "path": "/api/database",
  "httpMethod": "POST",
  "headers": {},
  "multiValueHeaders": {},
  "requestContext": {
    "resourceId": "test",
    "apiId": "test",
    "resourcePath": "/api/database",
    "httpMethod": "POST",
    "requestId": "test",
    "accountId": "123456789012",
    "stage": "local",
    "identity": {
      "sourceIp": "127.0.0.1"
    },
    "path": "/api/database"
  },
  "body": null,
  "isBase64Encoded": false
}
EOF

curl -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d @test-database.json
```

## Accessing Local Services

### PostgreSQL Database

**Using psql:**
```bash
docker exec -it postgres_lambda psql -U docker -d docker
```

**Using a GUI client** ([TablePlus](https://tableplus.com/), [Postico](https://eggerapps.at/postico/), etc.):
- Host: `localhost`
- Port: `5432`
- Username: `docker`
- Password: `docker`
- Database: `docker`

### MinIO (S3) Console

Access at: http://localhost:9001
- Username: `admin`
- Password: `password`

## Troubleshooting

### Lambda won't start

- Check that Docker Desktop is running
- Verify services started: `docker ps`
- Check Xcode console for error messages
- Ensure environment variables are set in Xcode scheme

### Can't connect to PostgreSQL

```bash
# Verify container is running
docker ps | grep postgres

# Test connection
docker exec -it postgres_lambda psql -U docker -d docker -c "\l"

# Check configuration
cat ~/.swiftSampleDemo/swiftLambdaDemo.json
```

### Can't connect to S3/MinIO

```bash
# Verify container is running
docker ps | grep minio

# Access web console
open http://localhost:9001

# Check bucket exists
docker exec minio_lambda ls -la /data/
```

### Port already in use

If you see the Lambda starting on port 7000 instead of 8080:

1. **Verify environment variable in Xcode**:
   - Product → Scheme → Edit Scheme → Run → Arguments
   - Check that `LOCAL_LAMBDA_PORT = 8080` is present and enabled

2. **Restart Xcode completely**:
   - Close Xcode (⌘Q)
   - Reopen and run again

3. **Check for port conflicts**:
```bash
# Check what's using port 8080
lsof -i :8080

# If port 7000 is showing up, it's likely macOS Control Center
lsof -i :7000
```

**Common Issue - Port 7000**: macOS Control Center (AirPlay Receiver) uses port 7000 by default. This is why we configure the Lambda to use port 8080 instead.

## Connecting to Remote AWS Services

To test against real AWS services instead of local Docker containers:

1. **Update configuration** (`~/.swiftSampleDemo/swiftLambdaDemo.json`):

```json
{
  "postgres": {
    "name": "production_db",
    "host": "your-rds-endpoint.us-east-1.rds.amazonaws.com",
    "port": 5432,
    "username": "admin",
    "userPassword": "your-password"
  },
  "s3": {
    "bucketName": "your-production-bucket",
    "endpoint": null
  }
}
```

2. **Update Xcode environment variables**:
   - Keep `LOCAL_LAMBDA_SERVER_ENABLED: true`
   - Change `MOCK_AWS_CREDENTIALS: false`

**Security Note:** Never commit AWS credentials to version control.

## Daily Development Workflow

### Option 1: Using Xcode UI

```bash
# 1. Start services (if not already running)
./tools.sh startServices

# 2. Make code changes
# Edit your Swift files in Xcode

# 3. Run in Xcode (⌘R)

# 4. Test with curl or Postman

# 5. Repeat steps 2-4

# 6. Stop services when done
./tools.sh stopServices
```

### Option 2: Using Command Line

```bash
# 1. Start services
./tools.sh startServices

# 2. Copy configuration
./tools.sh copyConfig

# 3. Run Lambda locally (foreground - will block terminal)
./tools.sh runLocalLambda 8080

# OR run in background
./tools.sh runLocalLambda 8080 bg

# 4. Test endpoints
./tools.sh testLocalLambda 8080

# 5. Stop Lambda (if running in background)
./tools.sh stopLocalLambda 8080

# 6. Stop services
./tools.sh stopServices
```

## Integration Testing

An automated integration test is available that tests the full local development workflow:

```bash
# Run the integration test
swift test --filter XcodeLocalIntegrationTests

# The test will:
# 1. Start local services (PostgreSQL + MinIO)
# 2. Start Lambda locally
# 3. Test S3 file upload/download
# 4. Test PostgreSQL database initialization
# 5. Stop Lambda
# 6. Stop services
```

**Note**: The integration test takes several minutes to complete because it:
- Builds the Lambda executable
- Starts Docker containers
- Waits for services to be ready
- Runs end-to-end API tests

See `/Users/bill/Developer/personal/swift-lambda-sample/Tests/SwiftDeployTests/XcodeDeployTests.swift` for the test implementation.

## Next Steps

- For building and deploying to AWS, see [RUN_LOCALLY_LINUX.md](RUN_LOCALLY_LINUX.md)
- For AWS deployment, see [CLAUDE.md](../CLAUDE.md)
- For development principles, see [PRINCIPLES.md](PRINCIPLES.md)
