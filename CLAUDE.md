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
- ✅ Thin delegator to SwiftDeploy
- ✅ Shorter prefix: `./tools.sh` vs `swift run SwiftDeploy`
- ✅ All logic in SwiftDeploy (single source of truth)

### Command Comparison

| Task | SwiftDeploy (Full) | tools.sh (Shortcut) |
|------|-------------------|---------------------|
| Deploy infrastructure | `swift run SwiftDeploy aws deploy` | `./tools.sh aws deploy` |
| Update Lambda code | `swift run SwiftDeploy aws update-lambda` | `./tools.sh aws update-lambda` |
| Start local services | `swift run SwiftDeploy local services start-all` | `./tools.sh local services start-all` |
| Test deployment | `swift run SwiftDeploy aws test all` | `./tools.sh aws test all` |
| Check logs | `swift run SwiftDeploy aws logs` | `./tools.sh aws logs` |
| Check status | `swift run SwiftDeploy aws status` | `./tools.sh aws status` |

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
# Copy the example config file (creates both app config and AWS config template)
swift run SwiftDeploy local copy-config

# Or create AWS config manually
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
swift run SwiftDeploy aws deploy
swift run SwiftDeploy aws status
```

**Option 2: Override with CLI flag**

```bash
# Use a different profile for this command
swift run SwiftDeploy aws deploy --aws-profile staging
swift run SwiftDeploy aws test all --aws-profile development
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
swift run SwiftDeploy aws deploy
swift run SwiftDeploy aws status
swift run SwiftDeploy aws test all
```

**Option 2: Use CLI flag**

```bash
# Use aws-vault for a single command
swift run SwiftDeploy aws deploy --use-aws-vault
swift run SwiftDeploy aws test all --use-aws-vault

# Override config to NOT use aws-vault for this command
# (if useAWSVault is true in config but you want to temporarily disable it)
swift run SwiftDeploy aws deploy  # Uses traditional credentials
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
# Run commands directly (full form)
swift run SwiftDeploy <command> [subcommand] [args...]

# Or use the tools.sh wrapper (shortcut)
./tools.sh <command> [subcommand] [args...]

# Examples
swift run SwiftDeploy aws deploy          # Full form
./tools.sh aws deploy                     # Shortcut

swift run SwiftDeploy local services start-all
./tools.sh local services start-all
```

### CLI Structure

The CLI is organized into two top-level commands:

```
SwiftDeploy
├── aws                          # All AWS operations
│   ├── deploy                   # Deploy/update infrastructure
│   ├── deploy-full             # Initial deployment (infrastructure + code)
│   ├── update-lambda            # Update Lambda code only
│   ├── tear-down                # Destroy infrastructure
│   ├── status                   # Check deployment status
│   ├── logs                     # Show Lambda CloudWatch logs
│   ├── get-url                  # Get API Gateway URL
│   └── test                     # Test deployed endpoints
│       ├── all                  # Run all endpoint tests
│       ├── s3-upload            # Test S3 upload/download endpoint
│       └── users                # Test user CRUD endpoints (requires DB)
│
└── local                        # Local development
    ├── services                 # Manage local services (PostgreSQL + MinIO)
    │   ├── start-all            # Start PostgreSQL + MinIO
    │   ├── stop-all             # Stop all services
    │   ├── start-database       # Start PostgreSQL only
    │   ├── stop-database        # Stop PostgreSQL only
    │   ├── start-s3             # Start MinIO only
    │   └── stop-s3              # Stop MinIO only
    ├── lambda                   # Lambda container testing
    │   ├── setup-network        # Setup Docker network
    │   ├── build                # Build Lambda for Linux
    │   ├── run-container        # Run Lambda container
    │   └── test                 # Test local endpoints
    └── copy-config              # Copy config files
```

### Commands

#### 1. Full Deploy (`aws deploy-full`)

**Full deployment**: Deploys CDK infrastructure + Lambda code. Use this for initial deployment or when you want to update everything.

**Default is minimal cost** (no database, no NAT Gateway).

**Basic usage:**
```bash
# Minimal deployment (default: no Postgres, no NAT)
swift run SwiftDeploy aws deploy-full
./tools.sh aws deploy-full

# Deploy with PostgreSQL (adds cost)
swift run SwiftDeploy aws deploy-full --with-postgres
./tools.sh aws deploy-full --with-postgres

# Full deployment (Postgres + NAT)
swift run SwiftDeploy aws deploy-full --with-postgres --with-nat-gateway
./tools.sh aws deploy-full --with-postgres --with-nat-gateway
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

#### 2. Deploy (`aws deploy`)

**Update infrastructure only**: Updates CDK infrastructure without touching Lambda code.

**Usage:**
```bash
# Update infrastructure (minimal)
swift run SwiftDeploy aws deploy
./tools.sh aws deploy

# Update infrastructure with database
swift run SwiftDeploy aws deploy --with-postgres
./tools.sh aws deploy --with-postgres
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
4. **Does NOT update Lambda code** (use `aws update-lambda` for that)

#### 3. Update Lambda (`aws update-lambda`)

**Update Lambda code only**: Updates Lambda code without touching infrastructure.

**Usage:**
```bash
# Update Lambda code
swift run SwiftDeploy aws update-lambda
./tools.sh aws update-lambda

# Update without pushing git commits
swift run SwiftDeploy aws update-lambda --skip-push
```

**What it does:**
1. Pushes git commits (if any) which triggers GitHub Actions
2. OR manually triggers GitHub Actions workflow
3. Waits for build and deployment to complete
4. **Does NOT update infrastructure** (use `aws deploy` for that)

#### 4. Tear Down (`aws tear-down`)

Safely destroys the entire CDK stack:

```bash
# Using Swift directly (with confirmation prompt)
swift run SwiftDeploy aws tear-down

# Using tools.sh wrapper
./tools.sh aws tear-down

# Skip confirmation prompt
swift run SwiftDeploy aws tear-down --force
```

**Warning**: This destroys ALL infrastructure including:
- Lambda function
- API Gateway
- S3 bucket (must be empty first)
- SQS queues
- VPC and networking resources
- RDS database (if deployed)
- All CloudWatch resources

#### 5. Status (`aws status`)

Check the current state of your deployment:

```bash
# Using Swift directly
swift run SwiftDeploy aws status

# Using tools.sh wrapper
./tools.sh aws status
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

#### 6. AWS Logs (`aws logs`)

**Show Lambda CloudWatch logs:**

```bash
# Show logs from last 5 minutes (default)
swift run SwiftDeploy aws logs
./tools.sh aws logs

# Show logs from last hour
swift run SwiftDeploy aws logs --since 1h
./tools.sh aws logs --since 1h
```

#### 7. Get URL (`aws get-url`)

**Get API Gateway URL from CloudFormation:**

```bash
swift run SwiftDeploy aws get-url
./tools.sh aws get-url
```

#### 8. Test Commands (`aws test`)

**Test deployed AWS Lambda endpoints:**

**Available subcommands:**
```bash
# Run all verification tests
swift run SwiftDeploy aws test all
./tools.sh aws test all

# Test S3 file upload/download endpoint
swift run SwiftDeploy aws test s3-upload
./tools.sh aws test s3-upload

# Test S3 endpoint with verbose curl output
swift run SwiftDeploy aws test s3-upload --verbose
./tools.sh aws test s3-upload --verbose

# Test user CRUD endpoints (requires PostgreSQL)
swift run SwiftDeploy aws test users
./tools.sh aws test users
```

**Example workflow:**
```bash
# 1. Deploy Lambda
swift run SwiftDeploy aws deploy-full

# 2. Run all tests
swift run SwiftDeploy aws test all

# 3. Or test individual components
swift run SwiftDeploy aws test s3-upload
swift run SwiftDeploy aws logs
```

#### 9. Local Development Commands (`local`)

**Manage local development environment**: Start/stop Docker services, test Lambda locally.

**Service Management:**
```bash
# Start all services (PostgreSQL + MinIO)
swift run SwiftDeploy local services start-all
./tools.sh local services start-all

# Stop all services
swift run SwiftDeploy local services stop-all
./tools.sh local services stop-all

# Start individual services
swift run SwiftDeploy local services start-database  # PostgreSQL only
swift run SwiftDeploy local services start-s3        # MinIO only

# Stop individual services
swift run SwiftDeploy local services stop-database
swift run SwiftDeploy local services stop-s3
```

**Lambda Container Testing:**
```bash
# Setup Docker network
swift run SwiftDeploy local lambda setup-network
./tools.sh local lambda setup-network

# Build Lambda for Linux
swift run SwiftDeploy local lambda build
./tools.sh local lambda build

# Run Lambda in interactive Linux container
swift run SwiftDeploy local lambda run-container
./tools.sh local lambda run-container

# Test local Lambda endpoints
swift run SwiftDeploy local lambda test
./tools.sh local lambda test
```

**Configuration:**
```bash
# Copy config files to ~/.swiftSampleDemo/
swift run SwiftDeploy local copy-config
./tools.sh local copy-config
```

**Example workflow:**
```bash
# 1. Start local services
swift run SwiftDeploy local services start-all

# 2. Build Lambda for Linux
./build.sh SwiftLambda

# 3. Run in container and test
swift run SwiftDeploy local lambda run-container
# Inside container: ./bootstrap

# 4. In another terminal, test endpoints
swift run SwiftDeploy local lambda test

# 5. Stop services when done
swift run SwiftDeploy local services stop-all
```

### Tools.sh Thin Wrapper

The `tools.sh` script is a **thin wrapper** that delegates all commands directly to SwiftDeploy. It provides a shorter command prefix for convenience.

**How it works:**
- `./tools.sh` simply runs `swift run SwiftDeploy` with all arguments passed through
- No logic or wrapper functions - just a delegator
- Single source of truth: all functionality is in SwiftDeploy

**Usage:**
```bash
# Show help (delegated to ArgumentParser)
./tools.sh --help
./tools.sh aws --help
./tools.sh local --help

# All commands are the same, just with shorter prefix
./tools.sh aws deploy                     # = swift run SwiftDeploy aws deploy
./tools.sh aws deploy-full --with-postgres
./tools.sh aws test all
./tools.sh local services start-all
```

**Example commands:**
```bash
# Deploy
./tools.sh aws deploy
./tools.sh aws deploy --with-postgres

# Update Lambda code only
./tools.sh aws update-lambda

# Test deployment
./tools.sh aws test all

# Check status
./tools.sh aws status

# Local development
./tools.sh local services start-all
./tools.sh local lambda build
```

### Typical Deployment Workflows

#### Initial Deployment
```bash
# 1. Deploy everything (minimal cost by default)
./tools.sh aws deploy-full

# 2. Verify deployment
./tools.sh aws test all

# 3. Check status
./tools.sh aws status
```

#### Update Lambda Code Only
```bash
# 1. Make changes to Swift code
vim Sources/SwiftLambda/APIGatewayHandler.swift

# 2. Commit changes
git add -A
git commit -m "Update API handler"

# 3. Update Lambda code (infrastructure unchanged)
./tools.sh aws update-lambda
```

#### Update Infrastructure Only
```bash
# 1. Modify CDK code
vim cdk/lib/constructs/lambda-construct.ts

# 2. Update infrastructure only (Lambda code unchanged)
./tools.sh aws deploy

# (Lambda code is NOT updated - use aws update-lambda if needed)
```

#### Full Deployment with Database
```bash
# Initial deployment with PostgreSQL and NAT Gateway
./tools.sh aws deploy-full --with-postgres --with-nat-gateway

# Or just add PostgreSQL
./tools.sh aws deploy-full --with-postgres
```

#### Clean Up
```bash
# Destroy all infrastructure
./tools.sh aws tear-down
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

**Note**: The `swift run SwiftDeploy aws deploy-full` command handles all of this automatically.

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
# Deploy infrastructure + Lambda code
swift run SwiftDeploy aws deploy-full
./tools.sh aws deploy-full

# Deploy with database
swift run SwiftDeploy aws deploy-full --with-postgres
./tools.sh aws deploy-full --with-postgres

# Check status
swift run SwiftDeploy aws status
./tools.sh aws status

# Update Lambda code only
swift run SwiftDeploy aws update-lambda
./tools.sh aws update-lambda

# Test deployment
swift run SwiftDeploy aws test all
./tools.sh aws test all

# Show logs
swift run SwiftDeploy aws logs
./tools.sh aws logs

# Destroy deployment
swift run SwiftDeploy aws tear-down
./tools.sh aws tear-down

# Get help
swift run SwiftDeploy --help
swift run SwiftDeploy aws --help
swift run SwiftDeploy local --help
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
