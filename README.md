# Swift Lambda Sample

## Summary

This repository demonstrates how to build and deploy a complete serverless application using **Swift on AWS Lambda**. It showcases best practices for Swift server development and provides a foundation for building scalable serverless APIs.

The project demonstrates integration with various AWS services:

* **API Gateway** - HTTP/S REST API endpoints
* **Lambda** - Swift-based serverless compute
* **RDS (PostgreSQL)** - Managed relational database with SSL/TLS
* **S3** - Object storage for file operations
* **SQS** - Message queuing with Dead Letter Queue
* **CloudWatch** - Scheduled invocations and logging
* **Secrets Manager** - Secure credential storage
* **VPC** - Network isolation with public/private subnets

The repository includes infrastructure-as-code using **AWS CDK (TypeScript)**, automated CI/CD via **GitHub Actions**, and a custom **SwiftDeploy CLI** for streamlined deployment management.

## Deployment

This project uses the **SwiftDeploy** CLI tool for managing AWS deployments. The tool handles both infrastructure (via CDK) and Lambda code deployment.

**Prerequisites:** Configure AWS credentials and profile (see [CLAUDE.md](CLAUDE.md#aws-profile-configuration) for details)

### Using aws-vault (MFA)

If you use aws-vault with MFA, create a wrapper script and credential_process profile:

```bash
# 1. Create wrapper script
cat > ~/.swiftSampleDemo/aws-vault-export.sh << 'EOF'
#!/bin/bash
export HOME=/Users/<your-username>
export AWS_VAULT_KEYCHAIN_NAME=login
exec /opt/homebrew/bin/aws-vault export --format=json <your-profile>
EOF
chmod +x ~/.swiftSampleDemo/aws-vault-export.sh

# 2. Add to ~/.aws/config
echo '[profile <your-profile>-vault]
region = us-east-1
credential_process = /Users/<your-username>/.swiftSampleDemo/aws-vault-export.sh' >> ~/.aws/config

# 3. Configure app to use the new profile
echo '{"profileName": "<your-profile>-vault", "useAWSVault": false}' > ~/.swiftSampleDemo/aws-config.json
```

Before using the CLI or Mac app, prime your session:
```bash
aws-vault exec <your-profile> -- echo "Session primed"
```

### Quick Start

Deploy with minimal AWS costs (no database, no NAT Gateway):

```bash
# Initial deployment
swift run SwiftDeploy aws deploy-full

# Or using the tools.sh wrapper
./tools.sh aws deploy-full
```

### Deployment Commands

| Command | Description |
|---------|-------------|
| `swift run SwiftDeploy aws deploy-full` | Initial deployment: CDK infrastructure + Lambda code |
| `swift run SwiftDeploy aws deploy` | Update CDK infrastructure only |
| `swift run SwiftDeploy aws update-lambda` | Update Lambda code only |
| `swift run SwiftDeploy aws status` | Check deployment status and outputs |
| `swift run SwiftDeploy aws tear-down` | Destroy all infrastructure |
| `swift run SwiftDeploy aws test all` | Test deployed endpoints |
| `swift run SwiftDeploy aws logs` | Show CloudWatch logs |

### Deployment Options

Control costs by choosing which resources to deploy:

```bash
# Minimal deployment (default: no Postgres, no NAT Gateway)
swift run SwiftDeploy aws deploy-full

# Include PostgreSQL database (~$15/month)
swift run SwiftDeploy aws deploy-full --with-postgres

# Full deployment with PostgreSQL and NAT Gateway (~$47/month)
swift run SwiftDeploy aws deploy-full --with-postgres --with-nat-gateway
```

### Using tools.sh Wrapper

The `tools.sh` script is a thin wrapper that delegates to SwiftDeploy:

```bash
# Deployment
./tools.sh aws deploy-full                    # Initial deployment
./tools.sh aws deploy-full --with-postgres    # With database
./tools.sh aws deploy                          # Update infrastructure
./tools.sh aws update-lambda                   # Update Lambda code
./tools.sh aws status                          # Check status
./tools.sh aws tear-down                       # Destroy everything

# Testing
./tools.sh aws test all                        # Run all tests
./tools.sh aws test s3-upload                  # Test S3 endpoint
./tools.sh aws logs                            # View logs
```

### Typical Workflows

**Initial Setup:**
```bash
./tools.sh aws deploy-full
./tools.sh aws test all
```

**Update Lambda Code:**
```bash
# Make changes to Swift code
vim Sources/SwiftLambda/APIGatewayHandler.swift

# Commit and deploy
git add -A && git commit -m "Update handler"
./tools.sh aws update-lambda
```

**Update Infrastructure:**
```bash
# Modify CDK code
vim cdk/lib/constructs/lambda-construct.ts

# Deploy infrastructure changes
./tools.sh aws deploy
```

For detailed deployment documentation, see [CLAUDE.md](CLAUDE.md).

## Local Development

There are three ways to run and test the Lambda locally:

1. **Native Mac via Xcode** - Best for active development and debugging
2. **Build for Linux** - Create deployment packages for AWS
3. **Linux Container** - Test in production-like environment

### Quick Start

**For daily development (Mac/Xcode):**
```bash
# Start local services
./tools.sh local copy-config
./tools.sh local services start-all

# Then run in Xcode (⌘R)
```

**For testing before AWS deployment:**
```bash
# Build and test in Linux container
./build.sh SwiftLambda
./tools.sh local services start-all
./tools.sh local lambda run-container

# Inside container:
./bootstrap
```

### Full Documentation

For complete instructions on all three approaches, see **[Running Locally Guide](docs/RUN_LOCALLY.md)**

The guide covers:
- Xcode setup and configuration
- Building for Linux/AWS Lambda
- Running in Docker containers
- Database and S3 access
- Troubleshooting common issues
- Switching between local and remote AWS services
    
## Connecting to Remote AWS Services

While local services are recommended for development, you can connect to remote AWS services when needed. See the [Running Locally Guide](docs/RUN_LOCALLY.md#connecting-to-remote-aws-services) for details on:

- AWS CLI configuration
- Updating local configuration for remote endpoints
- Security considerations

## GitHub Actions Setup

This section walks you through configuring GitHub Actions for automated Lambda deployment.

### Step 1: Update Workflow Variables

**File:** `.github/workflows/deploy_dev.yml`

Update these variables to match your project:

```yaml
productName: SwiftLambda        # Your Swift Package product name
lambdaName: swift-lambda-sample # Your Lambda function name
```

### Step 2: Enable Actions Permissions

1. Go to your GitHub repo → **Settings**
2. Click **Actions** → **General** in the left sidebar
3. Scroll to "Workflow permissions"
4. Select **"Read and write permissions"**
5. Click **Save**

### Step 3: Create the Environment

1. Go to **Settings** → **Environments**
2. Click **"New Environment"**
3. Name: `dev`
4. Click **"Configure environment"**

### Step 4: Configure Deployment Branches

Inside the `dev` environment:

1. Find "Deployment branches and tags"
2. Click dropdown → Select **"Selected branches and tags"**
3. Click **"Add deployment branch or tag rule"**
4. Type `dev` and click **Add rule**

### Step 5: Add Environment Secret (AWS_ROLE_ARN)

Inside the `dev` environment → "Environment secrets":

1. Click **"Add secret"**
2. Name: `AWS_ROLE_ARN`
3. Value: Your AWS OIDC Role ARN (e.g., `arn:aws:iam::123456789012:role/YourRole_GitHub_OIDC_Role`)

See [Creating an AWS OIDC Role](#creating-an-aws-oidc-role) below if you need to create one.

### Step 6: Add Environment Variable (AWS_REGION)

Inside the `dev` environment → "Environment variables":

1. Click **"Add variable"**
2. Name: `AWS_REGION`
3. Value: `us-east-1`

### Step 7: Add Repository Secret (PAT)

1. Go to **Settings** → **Secrets and variables** → **Actions**
2. Click **"New repository secret"**
3. Name: `SWIFT_PACKAGE_MANAGER_PAT`
4. Value: A GitHub Personal Access Token with `read:packages` permission

---

### Creating an AWS OIDC Role

If you don't have an OIDC role for GitHub Actions, create one using the AWS CLI:

**1. Create the trust policy file:**

```bash
cat << 'EOF' > /tmp/trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": "repo:<GITHUB_ORG>/<REPO_NAME>:*"
                }
            }
        }
    ]
}
EOF
```

Replace `<AWS_ACCOUNT_ID>`, `<GITHUB_ORG>`, and `<REPO_NAME>` with your values.

**2. Create the IAM role:**

```bash
aws iam create-role \
  --role-name <YourProject>_GitHub_OIDC_Role \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  --description "GitHub Actions OIDC role for <repo-name>"
```

**3. Attach Lambda deployment permissions:**

```bash
cat << 'EOF' > /tmp/lambda-deploy-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:UpdateFunctionCode",
                "lambda:GetFunction"
            ],
            "Resource": "arn:aws:lambda:us-east-1:<AWS_ACCOUNT_ID>:function:<lambda-function-name>"
        }
    ]
}
EOF

aws iam put-role-policy \
  --role-name <YourProject>_GitHub_OIDC_Role \
  --policy-name LambdaDeployPolicy \
  --policy-document file:///tmp/lambda-deploy-policy.json
```

**4. Get the Role ARN:**

```bash
aws iam get-role --role-name <YourProject>_GitHub_OIDC_Role --query "Role.Arn" --output text
```

Use this ARN for the `AWS_ROLE_ARN` environment secret in Step 5.

## Troubleshooting

### Accessing Local Postgres Database

It may be useful to login to the local postgres instance for viewing schemas and data.

1. **Get Container ID**: Retrieve with `docker ps -a`.
2. **Docker Access**: Gain access using `docker exec -it <container id> /bin/bash`.
3. **Run Postgres Commands**: Start with `psql` and then utilize commands to interact with databases and tables.
    - List all databases: \l
    - Connect to docker database: \c docker
    - List all tables: \dt

## Additional Documentation

- **[Running Locally Guide](docs/RUN_LOCALLY.md)** - Comprehensive local development guide
- **[CLAUDE.md](CLAUDE.md)** - Detailed deployment and AWS operations guide
- **[PRINCIPLES.md](docs/PRINCIPLES.md)** - Server development principles and best practices
- **[TODO.md](docs/TODO.md)** - Project roadmap and planned improvements
