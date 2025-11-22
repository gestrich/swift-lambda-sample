# Swift Lambda Sample - Development Notes

This document contains operational notes for working with this Swift Lambda application and its AWS infrastructure.

## Tooling Architecture

This project uses a clean separation between build, deployment, and local development:

### Tools Overview

```
build.sh           → Pure build (Bash + Docker)
                     - Compiles Swift Lambda for AWS (linux/amd64)
                     - Creates lambda.zip deployment package
                     - Used by GitHub Actions CI/CD
                     - Works everywhere (Mac, Linux, CI/CD)

SwiftDeploy        → Deployment + Testing + Local Dev (Swift CLI)
                     - CDK infrastructure deployment
                     - GitHub Actions monitoring
                     - AWS testing (endpoints, S3, logs)
                     - Local development services (Docker)
                     - Type-safe, testable Swift code
                     - Mac only (requires Swift toolchain)

tools.sh           → Convenience aliases (Bash wrapper)
                     - Optional shortcuts for SwiftDeploy commands
                     - All logic delegates to SwiftDeploy
                     - AWS testing helpers (curl, CloudFormation)
```

### Why This Architecture?

**build.sh (Bash)**
- ✅ No Swift required on host - uses Docker container
- ✅ Works in GitHub Actions without setup
- ✅ Cross-platform compatible
- ✅ Simple, focused on one task: building

**SwiftDeploy (Swift)**
- ✅ Type-safe deployment logic
- ✅ Testable infrastructure code
- ✅ Great local development UX
- ✅ Rich error handling
- ⚠️ Requires Swift toolchain (local Mac only)

**tools.sh (Bash wrapper)**
- ✅ Optional convenience layer
- ✅ Quick aliases: `./tools.sh deploy` vs `swift run SwiftDeploy deploy`
- ✅ AWS testing helpers that combine multiple commands

### Command Comparison

| Task | SwiftDeploy (Recommended) | tools.sh (Alias) |
|------|---------------------------|------------------|
| Deploy infrastructure | `swift run SwiftDeploy deploy` | `./tools.sh aws-deploy` |
| Update Lambda code | `swift run SwiftDeploy update-lambda` | `./tools.sh aws-update-lambda` |
| Start local services | `swift run SwiftDeploy local start-services` | `./tools.sh local-start-all` |
| Test deployment | `swift run SwiftDeploy test all` | `./tools.sh aws-test` |
| Check logs | `swift run SwiftDeploy test logs` | `./tools.sh aws-logs` |
| Check status | `swift run SwiftDeploy status` | `./tools.sh aws-status` |

## Project Structure

### Nested CDK Directory

This project has a **nested `cdk/` directory** that contains the AWS Cloud Development Kit (CDK) infrastructure code, which deploys the Lambda function and all supporting AWS services.

```
swift-lambda-sample/
├── Sources/              # Swift Lambda source code
│   ├── SwiftLambda/      # Lambda handler and API Gateway routing
│   └── SwiftServerApp/   # Business logic, database, S3, etc.
├── cdk/                  # AWS CDK infrastructure (TypeScript)
│   ├── lib/
│   │   ├── swift-lambda-stack.ts        # Main CDK stack
│   │   └── constructs/                  # Reusable infrastructure components
│   │       ├── vpc-construct.ts         # VPC networking
│   │       ├── lambda-construct.ts      # Lambda function
│   │       ├── api-gateway-construct.ts # API Gateway (PUBLIC endpoint)
│   │       ├── database-construct.ts    # RDS PostgreSQL
│   │       ├── queue-construct.ts       # SQS queues
│   │       ├── storage-construct.ts     # S3 bucket
│   │       └── monitoring-construct.ts  # CloudWatch Events
│   └── README.md         # Detailed CDK documentation
└── lambda_function_payload.zip  # Compiled Lambda deployment package
```

### What the CDK Deploys

The CDK infrastructure deploys:

1. **VPC** - Multi-AZ networking with public/private subnets
2. **RDS PostgreSQL** - Database instance in private subnet with SSL/TLS enabled
3. **Lambda Function** - Swift-based Lambda with VPC integration
4. **API Gateway** - **PUBLIC** REST API (REGIONAL endpoint)
5. **S3 Bucket** - For file storage operations
6. **SQS Queues** - Main queue + Dead Letter Queue
7. **CloudWatch Events** - Scheduled Lambda invocations
8. **Secrets Manager** - Database credentials
9. **IAM Roles** - Least-privilege permissions

## Working with AWS

### AWS Profile Configuration

This project requires an AWS profile to be configured for all AWS CLI and CDK operations.

#### Setting Up AWS Authentication

**Step 1: Configure your AWS profile**

Choose a profile name (e.g., `production`, `staging`, `dev`) and configure AWS credentials:

```bash
aws configure --profile production
```

This creates files:
- `~/.aws/credentials` - Contains access keys
  ```ini
  [production]
  aws_access_key_id = YOUR_ACCESS_KEY
  aws_secret_access_key = YOUR_SECRET_KEY
  ```

- `~/.aws/config` - Contains region settings
  ```ini
  [profile production]
  region = us-east-1
  output = json
  ```

**Step 2: Create AWS configuration file**

Create `~/.swiftSampleDemo/aws-config.json` with your AWS profile:

```bash
# Copy the example config file
swift run SwiftDeploy local copy-config

# Or create manually
mkdir -p ~/.swiftSampleDemo
cat > ~/.swiftSampleDemo/aws-config.json <<EOF
{
  "profileName": "production",
  "useAWSVault": false
}
EOF
```

**Configuration options:**
- `profileName`: AWS profile name to use (required)
- `useAWSVault`: Use aws-vault for credential management (default: false)

The SwiftDeploy CLI will automatically read the profile from this file. You can override it with the `--aws-profile` and `--use-aws-vault` flags if needed.

#### Using AWS Profiles

**Option 1: Use config file (recommended)**

```bash
# Profile is read from ~/.swiftSampleDemo/aws-config.json
swift run SwiftDeploy deploy
swift run SwiftDeploy status
```

**Option 2: Override with CLI flag**

```bash
# Use a different profile for this command
swift run SwiftDeploy deploy --aws-profile staging
swift run SwiftDeploy test all --aws-profile development
```

**Direct AWS CLI usage** (when not using SwiftDeploy)

When using AWS CLI commands directly, you must specify the profile:

```bash
# Deploy CDK infrastructure
cd cdk
cdk deploy --profile production

# View CloudFormation stacks
aws cloudformation describe-stacks \
  --stack-name SwiftLambdaSampleStack \
  --profile production

# View Lambda logs
aws logs tail /aws/lambda/swift-lambda-sample \
  --since 5m \
  --profile production

# Get API Gateway URL
aws cloudformation describe-stacks \
  --stack-name SwiftLambdaSampleStack \
  --profile production \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
  --output text

# View database secret
aws secretsmanager get-secret-value \
  --secret-id DatabaseDbPassword2D27F983-rXdFpMxOgXEI \
  --profile production

# List all secrets
aws secretsmanager list-secrets \
  --profile production
```

### Using AWS Vault for Credential Management

**aws-vault** is a tool that securely stores and accesses AWS credentials in your operating system's secure keystore. It provides better security than storing credentials in plaintext files.

#### Installation

```bash
# macOS
brew install --cask aws-vault

# Verify installation
which aws-vault
```

#### Setup

```bash
# Add your AWS credentials to aws-vault
aws-vault add production
# Enter your AWS Access Key ID and Secret Access Key when prompted

# Test the credentials
aws-vault exec production -- aws sts get-caller-identity
```

#### Configuring SwiftDeploy to Use aws-vault

**Option 1: Enable in config file (recommended)**

Update `~/.swiftSampleDemo/aws-config.json`:

```json
{
  "profileName": "production",
  "useAWSVault": true
}
```

Now all SwiftDeploy commands will use aws-vault automatically:

```bash
# These commands now use aws-vault
swift run SwiftDeploy deploy
swift run SwiftDeploy status
swift run SwiftDeploy test all
```

**Option 2: Use CLI flag**

```bash
# Use aws-vault for a single command
swift run SwiftDeploy deploy --use-aws-vault
swift run SwiftDeploy test all --use-aws-vault

# Override config to NOT use aws-vault for this command
# (if useAWSVault is true in config but you want to temporarily disable it)
swift run SwiftDeploy deploy  # Uses traditional credentials
```

#### How it Works

When `useAWSVault` is enabled, SwiftDeploy:
1. Wraps AWS CLI and CDK commands with `aws-vault exec <profile> --`
2. Removes `--profile` flags from commands (aws-vault handles authentication)
3. Credentials are injected via environment variables

**Traditional approach:**
```bash
aws cloudformation describe-stacks --profile production
cdk deploy --profile production
```

**With aws-vault:**
```bash
aws-vault exec production -- aws cloudformation describe-stacks
aws-vault exec production -- cdk deploy
```

SwiftDeploy handles this automatically when `useAWSVault: true`.

#### Benefits

- **Security**: Credentials stored in OS keychain (macOS Keychain, Windows Credential Manager, etc.)
- **No plaintext**: AWS credentials never stored in `~/.aws/credentials`
- **MFA support**: Works with multi-factor authentication
- **Session management**: Temporary credentials with automatic rotation

#### Troubleshooting

**Error: "aws-vault is not installed"**

Install aws-vault:
```bash
brew install --cask aws-vault
```

Or disable aws-vault in your config:
```json
{
  "profileName": "production",
  "useAWSVault": false
}
```

**Error: "profile not found"**

Add your profile to aws-vault:
```bash
aws-vault add production
```

## GitHub Actions Deployment

### Automated Deployment Pipeline

This project uses **GitHub Actions** for continuous deployment. Every push to the `dev` branch triggers:

1. **Build** - Compiles Swift Lambda in Docker container
2. **Test** - Runs unit tests (currently disabled)
3. **Deploy** - Updates Lambda function code via AWS CLI

#### Workflow Files

- **`.github/workflows/deploy_dev.yml`** - Triggers on pushes to `dev` branch
- **`.github/workflows/deploy.yml`** - Reusable deployment workflow
- **`.github/workflows/test.yml`** - Test workflow

#### Build Process

The GitHub Action runs:
```bash
./build.sh SwiftLambda linux/amd64 $GITHUB_TOKEN
aws lambda update-function-code \
  --function-name swift-lambda-sample \
  --zip-file fileb://lambda.zip
```

### Monitoring Deployments with GitHub CLI

The **`gh` command** provides real-time deployment monitoring:

#### Installation

```bash
# macOS
brew install gh

# Authenticate
gh auth login
```

#### Monitoring Commands

```bash
# List recent workflow runs
gh run list --repo gestrich/swift-lambda-sample --branch dev --limit 5

# Watch a specific run (auto-updates)
gh run watch --repo gestrich/swift-lambda-sample

# View logs from the latest run
gh run view --repo gestrich/swift-lambda-sample --log

# View logs from a specific run
gh run view 19216274273 --repo gestrich/swift-lambda-sample --log

# Check if the latest deployment succeeded
gh run list --repo gestrich/swift-lambda-sample --branch dev --limit 1 \
  --json status,conclusion \
  --jq '.[0] | "\(.status) - \(.conclusion)"'
```

#### Typical Deployment Flow

```bash
# 1. Make changes to Swift code
vim Sources/SwiftLambda/APIGatewayHandler.swift

# 2. Commit and push
git add -A
git commit -m "Update API handler"
git push origin dev

# 3. Monitor deployment
gh run watch --repo gestrich/swift-lambda-sample

# 4. Test the deployed Lambda
curl -X GET https://gmyk36woqc.execute-api.us-east-1.amazonaws.com/prod/api/users
```

## API Gateway URL

**Current Endpoint:**
```
https://gmyk36woqc.execute-api.us-east-1.amazonaws.com/prod/
```

**Note:** The API Gateway URL changes with each fresh deployment. Get the current URL from the deployment outputs or by running:
```bash
swift run SwiftDeploy status
```

### Testing Your Deployment

After deploying infrastructure, verify that Lambda code is deployed and working:

#### Quick Test (No Database Required)

The file endpoint tests S3 integration and Lambda execution:

```bash
# Test S3 file upload/download
curl -X POST https://{your-api-gateway-id}.execute-api.us-east-1.amazonaws.com/prod/api/file

# Expected response:
"File uploaded and downloaded"

# What this tests:
# ✓ API Gateway routing
# ✓ Lambda function execution (Swift code)
# ✓ S3 bucket access and permissions
# ✓ File upload to S3
# ✓ File download from S3
```

**Verify the S3 file was created:**
```bash
# Get bucket name from deployment outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name SwiftLambdaSampleStack \
  --profile production \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text)

# List files in bucket
aws s3 ls s3://$BUCKET_NAME/ --profile production

# Download and view the test file
aws s3 cp s3://$BUCKET_NAME/hello-world.text - --profile production
# Output: "Hello World! This data was written/read from S3."
```

**Check Lambda logs:**
```bash
aws logs tail /aws/lambda/swift-lambda-sample \
  --since 5m \
  --profile production
```

### Available Endpoints

#### File Operations (No Database Required)
```bash
# Upload and download S3 test file
curl -X POST https://{api-id}.execute-api.us-east-1.amazonaws.com/prod/api/file

# Response: "File uploaded and downloaded"
# This endpoint works without PostgreSQL deployed
```

#### Database Management (Requires PostgreSQL)
```bash
# Initialize/reset database
curl -X POST https://{api-id}.execute-api.us-east-1.amazonaws.com/prod/api/database

# Response: "Database Initialized"
# Note: Only works if deployed WITH PostgreSQL (without --skip-postgres)
```

#### User CRUD Operations (Requires PostgreSQL)
```bash
# Create user
curl -X POST https://{api-id}.execute-api.us-east-1.amazonaws.com/prod/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "password123",
    "firstName": "John",
    "lastName": "Doe",
    "nickName": "JD",
    "phone": "555-1234",
    "slackID": "U12345678"
  }'

# Get all users
curl -X GET https://{api-id}.execute-api.us-east-1.amazonaws.com/prod/api/users

# Get single user
curl -X GET https://{api-id}.execute-api.us-east-1.amazonaws.com/prod/api/users/{uuid}

# Update user
curl -X PUT https://{api-id}.execute-api.us-east-1.amazonaws.com/prod/api/users/{uuid} \
  -H "Content-Type: application/json" \
  -d '{...}'

# Delete user
curl -X DELETE https://{api-id}.execute-api.us-east-1.amazonaws.com/prod/api/users/{uuid}

# Note: User endpoints require PostgreSQL to be deployed
```

## SwiftDeploy CLI Tool

This project includes a **Swift-based CLI tool** (`SwiftDeploy`) for managing deployments. It provides a streamlined interface for deploying, destroying, and monitoring your AWS infrastructure.

### Installation & Usage

The CLI is built as part of the Swift package and can be run directly:

```bash
# Run commands directly
swift run SwiftDeploy <command>

# Or use the convenient tools.sh wrapper functions
./tools.sh <function-name>
```

### Commands

#### 1. Fresh Deploy (`fresh-deploy`)

**Initial deployment**: Deploys CDK infrastructure + Lambda code. Use this for the first deployment.

**Default is minimal cost** (no database, no NAT Gateway).

**Basic usage:**
```bash
# Minimal deployment (default: no Postgres, no NAT)
swift run SwiftDeploy fresh-deploy
./tools.sh aws-fresh-deploy

# Deploy with PostgreSQL (adds cost)
swift run SwiftDeploy fresh-deploy --with-postgres
./tools.sh aws-fresh-deploy --with-postgres

# Full deployment (Postgres + NAT)
swift run SwiftDeploy fresh-deploy --with-postgres --with-nat-gateway
./tools.sh aws-fresh-deploy --with-postgres --with-nat-gateway
```

**Options:**
```bash
--with-postgres         # Include PostgreSQL database (adds ~$15/month)
--with-nat-gateway      # Include NAT Gateway (adds ~$32/month)
--skip-push             # Don't push git commits
--aws-profile <name>    # AWS profile to use (reads from ~/.swiftSampleDemo/aws-config.json if not specified)
--cdk-directory <path>  # CDK directory path (default: cdk)
```

**What it does:**
1. Deploys CDK infrastructure (API Gateway, Lambda, S3, SQS, etc.)
2. Polls CloudFormation until complete
3. Displays stack outputs (API URLs, resource names)
4. Deploys Lambda code via GitHub Actions
5. Verifies deployment by testing API endpoint

#### 2. Deploy (`deploy`)

**Update infrastructure only**: Updates CDK infrastructure without touching Lambda code.

**Usage:**
```bash
# Update infrastructure (minimal)
swift run SwiftDeploy deploy
./tools.sh deploy

# Update infrastructure with database
swift run SwiftDeploy deploy --with-postgres
./tools.sh deploy --with-postgres
```

**Options:**
```bash
--with-postgres         # Include PostgreSQL database (adds ~$15/month)
--with-nat-gateway      # Include NAT Gateway (adds ~$32/month)
--aws-profile <name>    # AWS profile to use (reads from ~/.swiftSampleDemo/aws-config.json if not specified)
--cdk-directory <path>  # CDK directory path (default: cdk)
```

**What it does:**
1. Updates CDK infrastructure only
2. Polls CloudFormation until complete
3. Displays stack outputs
4. **Does NOT update Lambda code** (use `update-lambda` for that)

#### 3. Update Lambda (`update-lambda`)

**Update Lambda code only**: Updates Lambda code without touching infrastructure.

**Usage:**
```bash
# Update Lambda code
swift run SwiftDeploy update-lambda
./tools.sh aws-update-lambda

# Update without pushing git commits
swift run SwiftDeploy update-lambda --skip-push
```

**What it does:**
1. Pushes git commits (if any) which triggers GitHub Actions
2. OR manually triggers GitHub Actions workflow
3. Waits for build and deployment to complete
4. **Does NOT update infrastructure** (use `deploy` for that)

#### 4. Tear Down (`tear-down`)

Safely destroys the entire CDK stack:

```bash
# Using Swift directly (with confirmation prompt)
swift run SwiftDeploy tear-down

# Using tools.sh wrapper
./tools.sh aws-tear-down

# Skip confirmation prompt
swift run SwiftDeploy tear-down --force
```

**Warning**: This destroys ALL infrastructure including:
- Lambda function
- API Gateway
- S3 bucket (must be empty first)
- SQS queues
- VPC and networking resources
- RDS database (if deployed)
- All CloudWatch resources

#### 3. Status (`status`)

Check the current state of your deployment:

```bash
# Using Swift directly
swift run SwiftDeploy status

# Using tools.sh wrapper
./tools.sh aws-status
```

**Displays:**
- **Git status**: Uncommitted changes, commits to push, current branch
- **GitHub Actions**: Latest workflow status and conclusion
- **CDK Stack**: All CloudFormation outputs (API URL, Lambda ARN, bucket name, etc.)

**Example output:**
```
📊 Checking status...

📝 Git Status:
  Uncommitted changes: NO
  Commits to push: NO
  Current branch: dev

🔄 GitHub Actions:
  Latest workflow status: completed
  Conclusion: success

☁️  CDK Stack:
  ApiGatewayUrl: https://abc123.execute-api.us-east-1.amazonaws.com/prod/
  LambdaFunctionName: swift-lambda-sample
  BucketName: swiftlambdasamplestack-storagedatabucket-xyz
  ...
```

#### 5. Test (`test`)

**Test deployed AWS Lambda**: Verify endpoints, S3 files, and logs.

**Available subcommands:**
```bash
# Endpoint Testing
swift run SwiftDeploy test file             # Test S3 file endpoint
swift run SwiftDeploy test file-verbose     # Test with verbose curl output
swift run SwiftDeploy test verify-s3        # Verify S3 file creation
swift run SwiftDeploy test get-url          # Get API Gateway URL

# Monitoring
swift run SwiftDeploy test logs             # Show Lambda logs (last 5m)
swift run SwiftDeploy test logs --since 1h  # Show logs from last hour

# Comprehensive Testing
swift run SwiftDeploy test all              # Run all verification tests
```

**What it does:**
- Tests deployed Lambda endpoints
- Verifies S3 file operations
- Displays CloudWatch logs
- Combines multiple tests into comprehensive verification

**Example workflow:**
```bash
# 1. Deploy Lambda
swift run SwiftDeploy fresh-deploy

# 2. Run all tests
swift run SwiftDeploy test all

# 3. Or test individual components
swift run SwiftDeploy test file
swift run SwiftDeploy test verify-s3
swift run SwiftDeploy test logs
```

#### 6. Local Development (`local`)

**Manage local development environment**: Start/stop Docker services, test Lambda locally.

**Available subcommands:**
```bash
# Service Management
swift run SwiftDeploy local start-services   # Start PostgreSQL + MinIO
swift run SwiftDeploy local stop-services    # Stop all services
swift run SwiftDeploy local start-database   # Start PostgreSQL only
swift run SwiftDeploy local stop-database    # Stop PostgreSQL only
swift run SwiftDeploy local start-s3         # Start MinIO only
swift run SwiftDeploy local stop-s3          # Stop MinIO only

# Lambda Container Testing
swift run SwiftDeploy local setup-network    # Setup Docker network
swift run SwiftDeploy local run-container    # Run Lambda in Linux container
swift run SwiftDeploy local test --port 8080 # Test local Lambda endpoints

# Configuration
swift run SwiftDeploy local copy-config      # Copy runtime config to ~/.swiftSampleDemo/
```

**What it does:**
- Manages local PostgreSQL and MinIO (S3) Docker containers
- Sets up Docker networking for Lambda container testing
- Provides interactive Linux container for testing Lambda builds
- Tests local Lambda endpoints
- Copies runtime configuration file (swiftLambdaDemo.json) to home directory

**Example workflow:**
```bash
# 1. Start local services
swift run SwiftDeploy local start-services

# 2. Build Lambda for Linux
./build.sh SwiftLambda

# 3. Run in container and test
swift run SwiftDeploy local run-container
# Inside container: ./bootstrap

# 4. In another terminal, test endpoints
swift run SwiftDeploy local test --port 8080

# 5. Stop services when done
swift run SwiftDeploy local stop-services
```

### Tools.sh Wrapper Functions

For convenience, `tools.sh` provides wrapper functions with consistent naming:
- **AWS commands**: `aws-*` prefix for all AWS deployment and testing
- **Local commands**: `local-*` prefix for all local development

#### AWS Deployment Functions

| Function | Description |
|----------|-------------|
| `aws-fresh-deploy` | Initial deployment: CDK infrastructure + Lambda code |
| `aws-deploy` | Update CDK infrastructure only (does NOT update Lambda) |
| `aws-update-lambda` | Update Lambda code only (does NOT update infrastructure) |
| `aws-tear-down` | Destroy all infrastructure |
| `aws-status` | Check deployment and git status |
| `aws-logs` | Show Lambda CloudWatch logs |
| `aws-get-url` | Get API Gateway URL |

**Flags for aws-fresh-deploy and aws-deploy:**
```bash
./tools.sh aws-fresh-deploy                                  # Minimal (first deployment)
./tools.sh aws-fresh-deploy --with-postgres                  # Add database
./tools.sh aws-fresh-deploy --with-postgres --with-nat-gateway  # Full infrastructure

./tools.sh aws-deploy                    # Update infrastructure (minimal)
./tools.sh aws-deploy --with-postgres    # Update infrastructure with database
```

#### AWS Testing Functions

| Function | SwiftDeploy Equivalent |
|----------|------------------------|
| `aws-test` | `swift run SwiftDeploy test all` |
| `aws-test-file` | `swift run SwiftDeploy test file` |
| `aws-test-file-verbose` | `swift run SwiftDeploy test file-verbose` |
| `aws-verify-s3` | `swift run SwiftDeploy test verify-s3` |

#### Local Development Functions

| Function | Description |
|----------|-------------|
| `local-copy-config` | Copy config files to ~/.swiftSampleDemo/ (app + AWS) |
| `local-start-all` | Start PostgreSQL + MinIO |
| `local-stop-all` | Stop all services |
| `local-start-db` | Start PostgreSQL only |
| `local-stop-db` | Stop PostgreSQL only |
| `local-start-s3` | Start MinIO only |
| `local-stop-s3` | Stop MinIO only |
| `local-setup-network` | Setup Docker network |
| `local-run-container` | Run Lambda in Linux container |
| `local-test [port]` | Test local Lambda endpoints |

**Usage:**
```bash
# List available functions
./tools.sh

# Deploy (minimal cost by default)
./tools.sh aws-deploy

# Deploy with database
./tools.sh aws-deploy --with-postgres

# Update Lambda code only
./tools.sh aws-update-lambda

# Test your deployment
./tools.sh aws-test

# Check status
./tools.sh aws-status
```

### Typical Deployment Workflows

#### Initial Deployment
```bash
# 1. Deploy everything (minimal cost by default)
./tools.sh aws-fresh-deploy

# 2. Verify deployment
./tools.sh aws-test

# 3. Check status
./tools.sh aws-status
```

#### Update Lambda Code Only
```bash
# 1. Make changes to Swift code
vim Sources/SwiftLambda/APIGatewayHandler.swift

# 2. Commit changes
git add -A
git commit -m "Update API handler"

# 3. Update Lambda code (infrastructure unchanged)
./tools.sh aws-update-lambda
```

#### Update Infrastructure Only
```bash
# 1. Modify CDK code
vim cdk/lib/constructs/lambda-construct.ts

# 2. Update infrastructure only (Lambda code unchanged)
./tools.sh aws-deploy

# (Lambda code is NOT updated - use aws-update-lambda if needed)
```

#### Full Deployment with Database
```bash
# Initial deployment with PostgreSQL and NAT Gateway
./tools.sh aws-fresh-deploy --with-postgres --with-nat-gateway

# Or just add PostgreSQL
./tools.sh aws-fresh-deploy --with-postgres
```

#### Clean Up
```bash
# Destroy all infrastructure
./tools.sh aws-tear-down
```

## Common Development Tasks

### Deploying Infrastructure Changes (Manual Method)

If you prefer to use CDK directly instead of SwiftDeploy:

```bash
cd cdk

# Build TypeScript
npm run build

# Preview changes
cdk diff --profile production

# Deploy
cdk deploy --profile production --require-approval never

# View outputs
cdk deploy --profile production --outputs-file outputs.json
```

**Note**: The `SwiftDeploy fresh-deploy` command handles all of this automatically.

### Deploying Lambda Code Changes

Lambda code deploys automatically via GitHub Actions on push to `dev`:

```bash
# Make changes to Swift code
vim Sources/SwiftLambda/APIGatewayHandler.swift

# Commit and push
git add -A
git commit -m "Update handler"
git push origin dev

# Monitor deployment
gh run watch --repo gestrich/swift-lambda-sample
```

**Or manually via AWS CLI:**

```bash
# Build locally
./build-local.sh SwiftLambda

# Deploy
aws lambda update-function-code \
  --function-name swift-lambda-sample \
  --zip-file fileb://lambda.zip \
  --profile production
```

### Viewing Logs

```bash
# Tail live logs
aws logs tail /aws/lambda/swift-lambda-sample \
  --follow \
  --profile production

# View recent errors
aws logs tail /aws/lambda/swift-lambda-sample \
  --since 5m \
  --profile production \
  --filter-pattern "ERROR"

# Get logs from specific time
aws logs tail /aws/lambda/swift-lambda-sample \
  --since 1h \
  --profile production \
  --format short
```

### Database Access

The database credentials are stored in AWS Secrets Manager:

```bash
# Get database credentials
aws secretsmanager get-secret-value \
  --secret-id DatabaseDbPassword2D27F983-rXdFpMxOgXEI \
  --profile production \
  --query 'SecretString' \
  --output text | jq '.'

# Output:
# {
#   "password": "...",
#   "dbname": "FFMSampleLambdaDB",
#   "engine": "postgres",
#   "port": 5432,
#   "host": "swiftlambdasamplestack-databaseinstanceaa8a5fde-wmw0coj9qkzb.c7iq7v9yttnf.us-east-1.rds.amazonaws.com",
#   "username": "docker"
# }
```

## Important Configuration Notes

### Database Connection

The Lambda connects to RDS PostgreSQL with:
- **SSL/TLS**: REQUIRED (enabled via `PostgresConnection.Configuration.TLS.prefer`)
- **Database Name**: `FFMSampleLambdaDB` (not the instance identifier!)
- **Username**: `docker`
- **Password**: Retrieved from Secrets Manager JSON (`password` field)
- **Secret Parsing**: ConfigurationService extracts password from JSON secret

### API Gateway Path Prefix

The Lambda handler is configured to parse the `/api` prefix:

```swift
// Sources/SwiftLambda/APIGatewayHandler.swift
let leadingPathPart = "api"  // Strips /api from the path
```

So API Gateway URL structure is:
```
https://{api-id}.execute-api.us-east-1.amazonaws.com/prod/api/{resource}
                                                         ^^^^      ^^^^^^^^
                                                         stage     parsed by Lambda
```

### Environment Variables

The Lambda has these environment variables set by CDK:

- `POSTGRES_HOST` - RDS endpoint
- `POSTGRES_PORT` - `5432`
- `POSTGRES_USER_NAME` - `docker`
- `POSTGRES_DBNAME` - `FFMSampleLambdaDB` (actual DB name, not instance ID)
- `POSTGRES_PASSWORD_SECRET_ID` - Secrets Manager secret name
- `SQS_URL` - SQS queue URL
- `S3_BUCKET_NAME` - S3 bucket name

## Troubleshooting

### Lambda Can't Connect to Database

Check these in order:

1. **Security Groups**: Ensure Lambda SG can access RDS on port 5432
   ```bash
   aws ec2 describe-security-groups \
     --filters "Name=group-name,Values=SwiftLambdaSampleStack-Database*" \
     --profile production \
     --query 'SecurityGroups[0].IpPermissions'
   ```

2. **SSL/TLS**: RDS requires encrypted connections
   - Verify `PostgresConnection.Configuration.TLS.prefer` is enabled

3. **Database Name**: Must be `FFMSampleLambdaDB`, not the instance identifier

4. **Password**: Verify secret is being parsed as JSON
   ```swift
   // Extract password from JSON: secretJson["password"]
   ```

### API Gateway Returns 403

If you get authorization errors:
- The API is now PUBLIC (REGIONAL endpoint)
- No resource policy restrictions
- Should be accessible from anywhere

### Deployment Fails

```bash
# Check GitHub Actions status
gh run list --repo gestrich/swift-lambda-sample --branch dev --limit 1

# View failure logs
gh run view --repo gestrich/swift-lambda-sample --log-failed

# Check build logs
gh run view {run-id} --repo gestrich/swift-lambda-sample --log
```

## Quick Reference

### SwiftDeploy CLI (Recommended)
```bash
# Deploy infrastructure
swift run SwiftDeploy fresh-deploy
./tools.sh aws-fresh-deploy

# Deploy without database (minimal cost)
swift run SwiftDeploy fresh-deploy
./tools.sh aws-fresh-deploy

# Check status
swift run SwiftDeploy status
./tools.sh aws-status

# Destroy deployment
swift run SwiftDeploy tear-down
./tools.sh aws-tear-down

# Get help
swift run SwiftDeploy --help
swift run SwiftDeploy fresh-deploy --help
```

### CDK Commands (Manual Method)
```bash
cd cdk
npm run build              # Build TypeScript
cdk synth                 # Generate CloudFormation
cdk diff --profile production    # Preview changes
cdk deploy --profile production  # Deploy stack
cdk destroy --profile production # Destroy stack
```

### GitHub CLI
```bash
gh run list --repo gestrich/swift-lambda-sample --branch dev
gh run watch --repo gestrich/swift-lambda-sample
gh run view --log
```

### AWS CLI
```bash
# All commands use: --profile production

# Lambda
aws lambda get-function --function-name swift-lambda-sample
aws lambda update-function-code --function-name swift-lambda-sample --zip-file fileb://lambda.zip

# Logs
aws logs tail /aws/lambda/swift-lambda-sample --follow

# CloudFormation
aws cloudformation describe-stacks --stack-name SwiftLambdaSampleStack

# Secrets Manager
aws secretsmanager get-secret-value --secret-id {secret-name}
```

## Resources

- **CDK Documentation**: See `cdk/README.md` for detailed infrastructure docs
- **Project README**: See root `README.md` for local development setup
- **API Gateway URL**: https://gmyk36woqc.execute-api.us-east-1.amazonaws.com/prod/
- **GitHub Actions**: https://github.com/gestrich/swift-lambda-sample/actions
