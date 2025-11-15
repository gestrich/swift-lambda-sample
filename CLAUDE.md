# Swift Lambda Sample - Development Notes

This document contains operational notes for working with this Swift Lambda application and its AWS infrastructure.

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

This project uses the **`production` AWS profile** for all AWS CLI and CDK operations.

#### Setting Up the Production Profile

1. Configure AWS credentials with the production profile:
   ```bash
   aws configure --profile production
   ```

2. The profile will be stored in `~/.aws/credentials`:
   ```ini
   [production]
   aws_access_key_id = YOUR_ACCESS_KEY
   aws_secret_access_key = YOUR_SECRET_KEY
   ```

3. And `~/.aws/config`:
   ```ini
   [profile production]
   region = us-east-1
   output = json
   ```

#### Using the Production Profile

All AWS commands must specify `--profile production`:

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

#### 1. Deploy (`deploy`)

Deploys CDK infrastructure and Lambda code. **Default is minimal cost** (no database, no NAT Gateway).

**Basic usage:**
```bash
# Minimal deployment (default: no Postgres, no NAT)
swift run SwiftDeploy deploy
./tools.sh deploy

# Deploy with PostgreSQL (adds cost)
swift run SwiftDeploy deploy --with-postgres
./tools.sh deployWithPostgres

# Deploy with NAT Gateway (adds cost)
swift run SwiftDeploy deploy --with-nat-gateway
./tools.sh deployWithNAT

# Full deployment (Postgres + NAT)
swift run SwiftDeploy deploy --with-postgres --with-nat-gateway
./tools.sh deployFull
```

**Options:**
```bash
--with-postgres         # Include PostgreSQL database (adds ~$15/month)
--with-nat-gateway      # Include NAT Gateway (adds ~$32/month)
--infra-only            # Deploy infrastructure only (skip Lambda code)
--skip-push             # Don't push git commits
--aws-profile <name>    # AWS profile to use (default: production)
--cdk-directory <path>  # CDK directory path (default: cdk)
```

**What it does:**
1. Deploys/updates CDK infrastructure (API Gateway, Lambda, S3, SQS, etc.)
2. Polls CloudFormation until complete
3. Displays stack outputs (API URLs, resource names)
4. Deploys Lambda code via GitHub Actions (unless `--infra-only`)
5. Verifies deployment by testing API endpoint

**Examples:**
```bash
# Quick infrastructure-only update (no Lambda deployment)
swift run SwiftDeploy deploy --infra-only
./tools.sh deployInfraOnly

# Deploy everything with database support
swift run SwiftDeploy deploy --with-postgres
```

#### 2. Deploy Lambda (`deploy-lambda`)

Updates Lambda code only (no infrastructure changes). Useful for quick code updates.

**Usage:**
```bash
# Deploy Lambda code
swift run SwiftDeploy deploy-lambda
./tools.sh deployLambda

# Deploy without pushing git commits
swift run SwiftDeploy deploy-lambda --skip-push
```

**What it does:**
1. Pushes git commits (if any) which triggers GitHub Actions
2. OR manually triggers GitHub Actions workflow
3. Waits for build and deployment to complete

#### 3. Tear Down (`tear-down`)

Safely destroys the entire CDK stack:

```bash
# Using Swift directly (with confirmation prompt)
swift run SwiftDeploy tear-down

# Using tools.sh wrapper
./tools.sh deployTearDown

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
./tools.sh deployStatus
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

### Tools.sh Wrapper Functions

For convenience, `tools.sh` provides wrapper functions:

#### Deployment Functions

| Function | Description |
|----------|-------------|
| `deploy` | Deploy infrastructure + Lambda code (use flags for options) |
| `deployLambda` | Deploy Lambda code only (no infrastructure changes) |
| `deployTearDown` | Destroy all infrastructure |
| `deployStatus` | Check deployment and git status |

**Deploy function flags:**
```bash
./tools.sh deploy                    # Minimal (default: no Postgres, no NAT)
./tools.sh deploy --with-postgres    # Add PostgreSQL database
./tools.sh deploy --with-nat-gateway # Add NAT Gateway
./tools.sh deploy --with-postgres --with-nat-gateway  # Full infrastructure
./tools.sh deploy --infra-only       # CDK infrastructure only (skip Lambda)
```

#### Testing Functions

| Function | Description |
|----------|-------------|
| `testApiFile` | Test S3 file endpoint (automatically gets API Gateway URL) |
| `testApiFileVerbose` | Test S3 file endpoint with verbose curl output |
| `verifyS3File` | Verify S3 file was created and show content |
| `checkLambdaLogs` | Show Lambda execution logs (last 5 minutes) |
| `testDeployment` | Run all verification tests (API + S3 + Logs) |
| `getApiGatewayUrl` | Get the current API Gateway URL from CloudFormation |

**Usage:**
```bash
# List available functions
./tools.sh

# Deploy (minimal cost by default)
./tools.sh deploy

# Deploy with database
./tools.sh deploy --with-postgres

# Update Lambda code only
./tools.sh deployLambda

# Test your deployment
./tools.sh testDeployment

# Check status
./tools.sh deployStatus
```

### Typical Deployment Workflows

#### Initial Deployment
```bash
# 1. Deploy everything (minimal cost by default)
./tools.sh deploy

# 2. Verify deployment
./tools.sh testDeployment

# 3. Check status
./tools.sh deployStatus
```

#### Update Lambda Code Only
```bash
# 1. Make changes to Swift code
vim Sources/SwiftLambda/APIGatewayHandler.swift

# 2. Commit changes
git add -A
git commit -m "Update API handler"

# 3. Deploy Lambda code (infrastructure unchanged)
./tools.sh deployLambda
```

#### Update Infrastructure Only
```bash
# 1. Modify CDK code
vim cdk/lib/constructs/lambda-construct.ts

# 2. Deploy infrastructure changes only (skip Lambda code)
./tools.sh deploy --infra-only

# 3. Optionally deploy Lambda code separately
./tools.sh deployLambda
```

#### Full Deployment with Database
```bash
# Deploy with PostgreSQL and NAT Gateway
./tools.sh deploy --with-postgres --with-nat-gateway

# Or just add PostgreSQL
./tools.sh deploy --with-postgres
```

#### Clean Up
```bash
# Destroy all infrastructure
./tools.sh deployTearDown
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
./tools.sh deployFresh

# Deploy without database (minimal cost)
./tools.sh deployFreshNoPostgres

# Check status
swift run SwiftDeploy status
./tools.sh deployStatus

# Destroy deployment
swift run SwiftDeploy tear-down
./tools.sh deployTearDown

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
