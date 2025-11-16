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

| Variable | Value |
|----------|-------|
| `LOCAL_LAMBDA_SERVER_ENABLED` | `true` |
| `MOCK_AWS_CREDENTIALS` | `true` |

### 4. Run in Xcode

1. Select the **SwiftLambda** target
2. Select **My Mac** as the destination
3. Click the **Run** button (or press ⌘R)

The Lambda will start a local HTTP server on port 7000.

### 5. Test the API

```bash
# Test S3 file upload/download (no database required)
curl -X POST http://localhost:7000/invoke \
  -H "Content-Type: application/json" \
  -d @test-api-gateway-event.json

# Expected: Success response with S3 file operations
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

curl -X POST http://localhost:7000/invoke \
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

curl -X POST http://localhost:7000/invoke \
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

```bash
# Check what's using port 7000
lsof -i :7000

# Kill the process if needed
kill -9 <PID>
```

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

## Next Steps

- For building and deploying to AWS, see [RUN_LOCALLY_LINUX.md](RUN_LOCALLY_LINUX.md)
- For AWS deployment, see [CLAUDE.md](../CLAUDE.md)
- For development principles, see [PRINCIPLES.md](PRINCIPLES.md)
