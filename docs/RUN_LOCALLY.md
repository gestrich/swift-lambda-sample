# Running Swift Lambda Locally

This guide covers multiple approaches for running and testing the Swift Lambda function locally during development.

## Overview

There are three ways to run the Lambda locally, each suited for different use cases:

1. **Native Mac via Xcode** - Best for active development and debugging
2. **Build for Linux** - Create deployment packages for AWS
3. **Linux Container** - Test in production-like environment

---

## Option 1: Running on Mac via Xcode (Recommended for Development)

This approach runs the Lambda natively on your Mac, making it easy to debug with Xcode breakpoints and Swift tooling.

### Prerequisites

- Xcode installed
- Docker Desktop installed and running
- [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install)

### Setup Steps

#### 1. Copy Configuration File

```bash
./tools.sh copyConfig
```

This copies `swiftLambdaDemo.json` to `~/.swiftSampleDemo/swiftLambdaDemo.json` with local service configuration.

#### 2. Configure Xcode Environment Variables

In Xcode, edit the scheme for the **SwiftLambda** target and add these environment variables:

| Variable | Value |
|----------|-------|
| `LOCAL_LAMBDA_SERVER_ENABLED` | `true` |
| `MOCK_AWS_CREDENTIALS` | `true` |

**How to set environment variables in Xcode:**
1. Product → Scheme → Edit Scheme
2. Select "Run" in the left sidebar
3. Click "Arguments" tab
4. Add to "Environment Variables" section

#### 3. Start Local Services

Start PostgreSQL and MinIO (S3-compatible storage):

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

#### 4. Run in Xcode

1. Select the **SwiftLambda** target
2. Select **My Mac** as the destination
3. Click the **Run** button (or press ⌘R)

The Lambda will start a local HTTP server (typically on port 7000 or 8080).

#### 5. Test the API

Use curl, Postman, or any HTTP client:

```bash
# Test S3 file upload/download (no database required)
curl -X POST http://localhost:7000/api/file

# Expected response:
"File uploaded and downloaded"
```

**Using Postman:**
- Download from [Postman](https://www.postman.com/downloads)
- TODO: Share Postman collection with sample API calls

### Stopping Services

```bash
./tools.sh stopServices
```

### Troubleshooting Xcode Development

**Lambda won't start:**
- Check that Docker Desktop is running
- Verify services started: `docker ps`
- Check Xcode console for error messages

**Can't connect to PostgreSQL:**
- Verify PostgreSQL container is running: `docker ps | grep postgres`
- Check connection settings in `~/.swiftSampleDemo/swiftLambdaDemo.json`
- Test connection: `docker exec -it postgres_lambda psql -U docker -d docker`

**Can't connect to S3/MinIO:**
- Verify MinIO container is running: `docker ps | grep minio`
- Access MinIO console: http://localhost:9001 (login: admin/password)
- Check bucket exists: `org.gestrich.sandbox`

---

## Option 2: Building Locally for Linux

Build the Lambda deployment package on your Mac for deployment to AWS Lambda.

### Build Command

```bash
# Build for Linux (AWS Lambda architecture)
./build.sh SwiftLambda

# Output: lambda.zip (ready for AWS deployment)
```

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

### Deploying the Built Package

```bash
# Deploy via AWS CLI
aws lambda update-function-code \
  --function-name swift-lambda-sample \
  --zip-file fileb://lambda.zip \
  --profile production

# Or push to trigger GitHub Actions deployment
git add -A
git commit -m "Update Lambda code"
git push origin dev
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

## Option 3: Running in Linux Container (Testing Production Environment)

Test your Lambda in a Linux container that matches the AWS Lambda runtime environment.

### Why Use This Option?

- Test in the exact same Linux environment as AWS Lambda
- Verify compiled binary works correctly on Amazon Linux 2
- Debug Linux-specific issues before deploying to AWS
- Test with production-like networking between containers

### Quick Start (3 Steps)

```bash
# 1. Build the Lambda for Linux
./build.sh SwiftLambda

# 2. Start local services (PostgreSQL + MinIO)
./tools.sh startServices

# 3. Run Lambda in container (auto-configures network and environment)
./tools.sh runLambdaContainer
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

The Lambda will start a local server on port 8080.

### Testing the Lambda

In another terminal (on your Mac):

```bash
# Test S3 file endpoint
curl -X POST http://localhost:8080/api/file

# Expected response:
"File uploaded and downloaded"

# Test database endpoint (requires PostgreSQL)
curl -X POST http://localhost:8080/api/database

# Test user CRUD endpoints
curl -X GET http://localhost:8080/api/users
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
./tools.sh setupLambdaNetwork
```

This creates the network and connects the services, then provides instructions for running the container manually.

### Available Container Management Commands

| Command | Description |
|---------|-------------|
| `./tools.sh setupLambdaNetwork` | Setup Docker network for containers |
| `./tools.sh runLambdaContainer` | Run Lambda in interactive container (recommended) |

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
-p 8081:8080  # Maps host port 8081 to container port 8080
```

**Lambda container exits immediately:**

- Check that `lambda` directory exists: `ls -la lambda/`
- Verify bootstrap is present: `ls -la lambda/bootstrap`
- Review Docker logs: `docker logs <container-id>`

---

## Accessing Local PostgreSQL Database

It's useful to inspect the local PostgreSQL database to view schemas and data.

### Using psql Inside Container

```bash
# Get container ID
docker ps -a

# Access container
docker exec -it postgres_lambda /bin/bash

# Run psql
psql -U docker -d docker

# Useful psql commands:
# \l                 - List all databases
# \c docker          - Connect to 'docker' database
# \dt                - List all tables
# \d table_name      - Describe table structure
# SELECT * FROM ...  - Query data
# \q                 - Quit psql
```

### Direct psql Access from Mac

```bash
# Execute psql command directly
docker exec -it postgres_lambda psql -U docker -d docker

# List all tables
docker exec -it postgres_lambda psql -U docker -d docker -c "\dt"

# Query data
docker exec -it postgres_lambda psql -U docker -d docker -c "SELECT * FROM users;"
```

### Using a Database GUI

Connect with tools like:
- [TablePlus](https://tableplus.com/)
- [pgAdmin](https://www.pgadmin.org/)
- [Postico](https://eggerapps.at/postico/)

**Connection settings:**
- Host: `localhost`
- Port: `5432`
- Username: `docker`
- Password: `docker`
- Database: `docker`

---

## Accessing MinIO (Local S3)

MinIO provides a web console for browsing S3 buckets.

### MinIO Console

Access the console at: http://localhost:9001

**Login credentials:**
- Username: `admin`
- Password: `password`

### MinIO CLI (mc)

Install the MinIO client:

```bash
brew install minio/stable/mc
```

Configure connection:

```bash
mc alias set local http://localhost:9000 admin password
```

Use MinIO CLI:

```bash
# List buckets
mc ls local

# List files in bucket
mc ls local/org.gestrich.sandbox

# Download file
mc cp local/org.gestrich.sandbox/hello-world.text ./

# Upload file
mc cp myfile.txt local/org.gestrich.sandbox/
```

---

## Connecting to Remote AWS Services

While local services are recommended for development, you may occasionally need to connect to remote AWS services.

### Prerequisites

1. **AWS CLI installed and configured**
   - Follow the [AWS CLI Getting Started Guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html)
   - Configure with: `aws configure --profile production`

2. **Update local configuration**
   - Modify `~/.swiftSampleDemo/swiftLambdaDemo.json`
   - Update service endpoints to point to AWS

3. **Xcode environment variables**
   - Set `LOCAL_LAMBDA_SERVER_ENABLED: true`
   - Set `MOCK_AWS_CREDENTIALS: false`

### Example Remote Configuration

Edit `~/.swiftSampleDemo/swiftLambdaDemo.json`:

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

**Security Note:** Never commit AWS credentials or production endpoints to version control.

---

## Switching Between Environments

### Quick Environment Switching

```bash
# Use local services
./tools.sh copyConfig
./tools.sh startServices

# Modify swiftLambdaDemo.json for remote AWS services
vim ~/.swiftSampleDemo/swiftLambdaDemo.json
```

### Environment-Specific Config Files

Consider maintaining separate config files:

```bash
# Local development
cp swiftLambdaDemo.json ~/.swiftSampleDemo/swiftLambdaDemo.json

# Remote AWS (keep this file OUT of git)
cp swiftLambdaDemo-aws.json ~/.swiftSampleDemo/swiftLambdaDemo.json
```

---

## Common Development Workflows

### Daily Development Workflow

```bash
# 1. Start services (if not already running)
./tools.sh startServices

# 2. Make code changes
vim Sources/SwiftServerApp/YourFile.swift

# 3. Run in Xcode (⌘R)
# 4. Test with curl or Postman
# 5. Repeat

# 6. Stop services when done
./tools.sh stopServices
```

### Testing Before AWS Deployment

```bash
# 1. Build for Linux
./build.sh SwiftLambda

# 2. Start services
./tools.sh startServices

# 3. Run in Linux container
./tools.sh runLambdaContainer

# 4. Inside container, run Lambda
./bootstrap

# 5. Test from another terminal
curl -X POST http://localhost:8080/api/file

# 6. If tests pass, deploy to AWS
./tools.sh updateLambda
```

### Troubleshooting Checklist

When things don't work:

1. ✅ Docker Desktop is running
2. ✅ Services are running: `docker ps`
3. ✅ Configuration file exists: `ls ~/.swiftSampleDemo/swiftLambdaDemo.json`
4. ✅ Xcode environment variables are set
5. ✅ No port conflicts: `lsof -i :7000` or `lsof -i :8080`
6. ✅ Check logs in Xcode console
7. ✅ Check Docker logs: `docker logs postgres_lambda` or `docker logs minio_lambda`

---

## Additional Resources

- [Main README](../README.md) - Project overview and deployment
- [CLAUDE.md](../CLAUDE.md) - Detailed AWS deployment and operations guide
- [PRINCIPLES.md](PRINCIPLES.md) - Server development principles and best practices
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [Swift AWS Lambda Runtime](https://github.com/swift-server/swift-aws-lambda-runtime)
