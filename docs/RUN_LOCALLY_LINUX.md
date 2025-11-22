# Running Swift Lambda Locally with Linux Containers

This guide covers building and running the Swift Lambda function in Linux containers that match the AWS Lambda runtime environment.

## When to Use This

- **Pre-deployment testing** - Verify your build works in the AWS Lambda environment
- **Linux-specific debugging** - Test compiled binaries on Amazon Linux 2
- **Production validation** - Test with production-like container networking
- **CI/CD pipelines** - Build deployment packages for AWS

## Prerequisites

- Docker Desktop installed and running ([Download](https://docs.docker.com/desktop/install/mac-install))

---

## Building Linux Container

Build the Lambda for the Linux/Amazon Linux 2 environment that AWS Lambda uses.

### Quick Start

```bash
# Build for Linux (AWS Lambda architecture)
./build.sh SwiftLambda
```

This creates:
- `lambda.zip` - Deployment package for AWS
- `lambda/` directory - Contains the compiled binary and dependencies

### What the Build Does

The build script:
- Uses Docker to compile Swift code for **Amazon Linux 2** (AWS Lambda environment)
- Resolves and compiles all Swift package dependencies
- Strips debug symbols to reduce package size
- Creates `lambda.zip` deployment package
- Shows package size vs AWS Lambda 50MB limit

### Build Output

```
Building SwiftLambda for platform linux/amd64
AWS Lambda Architecture: x86_64 (amd64)
=========================================

Building Docker image...
Compiling application...
Stripping debug symbols...
Packaging to zip...

Lambda package size:
====================
  lambda.zip: 35M (36700160 bytes)
  AWS Lambda limit: 50 MB (52428800 bytes)
  Usage: 70.0%
  ✅ Package size is within AWS Lambda limits

✅ Build complete!
Lambda package: /path/to/lambda.zip
```

### Build Options

```bash
# Default: linux/amd64 (AWS Lambda x86_64)
./build.sh SwiftLambda

# With explicit platform
./build.sh SwiftLambda linux/amd64

# With GitHub token (for private dependencies)
./build.sh SwiftLambda linux/amd64 $GITHUB_TOKEN
```

### Build Troubleshooting

**Docker errors:**
- Ensure Docker Desktop is running
- Check Docker has enough resources (Memory: 4GB+, Disk: 20GB+)

**Build fails with permission errors:**
- The script automatically handles permissions for Mac/Linux
- Try cleaning: `rm -rf .aws-sam/build-SwiftLambda lambda lambda.zip`

**Package too large:**
- Check the size breakdown in build output
- Consider using Lambda Layers for large dependencies
- Review dependencies in `Package.swift`

---

## Deploying to AWS

Once you've built the Linux container, you can deploy it to AWS Lambda.

### Deploy via AWS CLI

```bash
aws lambda update-function-code \
  --function-name swift-lambda-sample \
  --zip-file fileb://lambda.zip \
  --profile production
```

### Deploy via SwiftDeploy CLI

```bash
# Update Lambda code only (doesn't change infrastructure)
./tools.sh aws-update-lambda
```

See [CLAUDE.md](../CLAUDE.md) for more deployment options.

---

## Running in Linux Container

Test your Lambda in a Linux container that matches the AWS Lambda runtime environment.

### Why Use This?

- Test in the exact same Linux environment as AWS Lambda
- Verify compiled binary works correctly on Amazon Linux 2
- Debug Linux-specific issues before deploying to AWS
- Test with production-like networking between containers

### Prerequisites

You must build the Lambda first (see section above):

```bash
./build.sh SwiftLambda
```

This creates the `lambda/` directory with the compiled bootstrap executable.

### Quick Start

```bash
# 1. Start local services (PostgreSQL + MinIO)
./tools.sh local-start-all

# 2. Run Lambda in container (auto-configures network and environment)
./tools.sh local-run-container
```

### What `runLambdaContainer` Does

The automated function:
1. Verifies the `lambda` directory exists (from build)
2. Creates the `lambda-local` Docker network
3. Connects PostgreSQL container to the network
4. Connects MinIO container to the network
5. Starts an interactive Swift container with:
   - Lambda code mounted at `/var/task`
   - Port 8080 exposed for HTTP requests
   - All environment variables configured
   - Network access to PostgreSQL and MinIO

### Running the Lambda

Once inside the container:

```bash
# The Lambda is ready to run (bootstrap is already executable)
./bootstrap
```

The Lambda will start a local server listening on all interfaces (0.0.0.0) on port 7000, which is exposed to your host machine on port 8080.

### Testing the Lambda

In another terminal (on your Mac):

```bash
# Test S3 file endpoint using API Gateway event payload
curl -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d @test-api-gateway-event.json

# Expected response includes:
# {"statusCode":200,"body":"\"File uploaded and downloaded\""}
```

**Note**: The local Lambda server uses the `/invoke` endpoint and expects API Gateway event payloads. See `test-api-gateway-event.json` for example format.

### Testing Different Endpoints

#### File Upload/Download (S3)

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

#### Database Operations

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

### Verify Services Before Running

Check that services are running:

```bash
docker ps
```

You should see:
- `postgres_lambda` - PostgreSQL database
- `minio_lambda` - S3-compatible storage

### Manual Network Setup (Alternative)

If you prefer to set up the network manually:

```bash
# Setup the Docker network only (without starting Lambda container)
./tools.sh local-setup-network
```

This creates the network and connects the services, then provides instructions for running the container manually.

### Available Container Management Commands

| Command | Description |
|---------|-------------|
| `./tools.sh local-setup-network` | Setup Docker network for containers |
| `./tools.sh local-run-container` | Run Lambda in interactive container (recommended) |

### Container Networking Details

When running in the Docker network, containers communicate using container names as hostnames:

- **PostgreSQL**: `POSTGRES_HOST=postgres_lambda`
- **MinIO**: `AWS_ENDPOINT_URL=http://minio_lambda:9000`

The `runLambdaContainer` function automatically configures these environment variables:

```bash
POSTGRES_HOST=postgres_lambda
POSTGRES_PORT=5432
POSTGRES_USER_NAME=docker
POSTGRES_DBNAME=docker
POSTGRES_PASSWORD=docker
S3_BUCKET_NAME=org.gestrich.sandbox
AWS_ENDPOINT_URL=http://minio_lambda:9000
AWS_ACCESS_KEY_ID=admin
AWS_SECRET_ACCESS_KEY=password
MOCK_AWS_CREDENTIALS=true
LOCAL_LAMBDA_SERVER_ENABLED=true
LOCAL_LAMBDA_HOST=0.0.0.0
```

### Troubleshooting Container Network

**Lambda can't connect to PostgreSQL:**

1. Verify services are running:
   ```bash
   docker ps
   # Should show: postgres_lambda and minio_lambda
   ```

2. Check network setup:
   ```bash
   docker network inspect lambda-local
   # Should show both containers connected
   ```

3. Test connectivity from Lambda container:
   ```bash
   # Inside the Lambda container
   ping postgres_lambda
   ping minio_lambda
   ```

4. Check PostgreSQL is accepting connections:
   ```bash
   # From your Mac
   docker exec -it postgres_lambda psql -U docker -d docker -c "\l"
   ```

**Port 8080 already in use:**

Check what's using the port:
```bash
lsof -i :8080
```

Kill the process or use a different port:
```bash
# Modify the docker run command to use different port
-p 8081:7000  # Maps host port 8081 to container port 7000
```

**Lambda container exits immediately:**

- Check that `lambda` directory exists: `ls -la lambda/`
- Verify bootstrap is present: `ls -la lambda/bootstrap`
- Review Docker logs: `docker logs <container-id>`

**Can't connect to Lambda server from host:**

- Ensure `LOCAL_LAMBDA_HOST=0.0.0.0` environment variable is set
- Check Lambda server logs show `host='0.0.0.0' port=7000`
- Verify port mapping is correct: `-p 8080:7000`

---

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

**Useful psql commands:**
```sql
\l                 -- List all databases
\c docker          -- Connect to 'docker' database
\dt                -- List all tables
\d table_name      -- Describe table structure
SELECT * FROM ...  -- Query data
\q                 -- Quit psql
```

### MinIO (S3) Console

Access at: http://localhost:9001
- Username: `admin`
- Password: `password`

**MinIO CLI (mc):**
```bash
# Install
brew install minio/stable/mc

# Configure
mc alias set local http://localhost:9000 admin password

# List files
mc ls local/org.gestrich.sandbox

# Download file
mc cp local/org.gestrich.sandbox/hello-world.text ./
```

---

## Testing Before AWS Deployment

### Complete Pre-Deployment Workflow

```bash
# 1. Build for Linux
./build.sh SwiftLambda

# 2. Start services
./tools.sh local-start-all

# 3. Run in Linux container
./tools.sh local-run-container

# 4. Inside container, run Lambda
./bootstrap

# 5. Test from another terminal
curl -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d @test-api-gateway-event.json

# 6. If tests pass, deploy to AWS
./tools.sh aws-update-lambda
```

### Verification Checklist

Before deploying to AWS:

- ✅ Lambda builds successfully without errors
- ✅ Package size is within AWS Lambda limits (50MB)
- ✅ Lambda runs in Linux container without crashes
- ✅ All API endpoints respond correctly with `/invoke` and API Gateway payloads
- ✅ Database connections work
- ✅ S3 operations succeed
- ✅ No environment-specific errors in logs

---

## Common Development Tasks

### Rebuilding After Code Changes

```bash
# 1. Make changes to Swift code
vim Sources/SwiftLambda/APIGatewayHandler.swift

# 2. Rebuild for Linux
./build.sh SwiftLambda

# 3. Test in container
./tools.sh local-run-container
./bootstrap
```

### Cleaning Build Artifacts

```bash
# Remove all build artifacts
rm -rf .aws-sam/build-SwiftLambda lambda lambda.zip

# Then rebuild
./build.sh SwiftLambda
```

### Stopping Services

```bash
# Stop PostgreSQL and MinIO
./tools.sh local-stop-all

# Stop specific container
docker stop postgres_lambda
docker stop minio_lambda
```

---

## Next Steps

- For Xcode/Mac development, see [RUN_LOCALLY_XCODE.md](RUN_LOCALLY_XCODE.md)
- For AWS deployment, see [CLAUDE.md](../CLAUDE.md)
- For development principles, see [PRINCIPLES.md](PRINCIPLES.md)
