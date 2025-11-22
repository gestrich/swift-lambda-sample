# Swift Lambda Sample

## Summary

This repository demonstrates how to build and deploy a complete serverless application using **Swift on AWS Lambda**. It showcases best practices for Swift server development and provides a production-ready foundation for building scalable serverless APIs.

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

## GitHub Action Setup

1. **deploy_dev.yml**: Update these variables.
    - productName: Swift Package product name
    - lambdaName: Name of the Lambda
2. **GitHub Settings Configuration**
    * Actions
        * General
            * Select "Read and write permissions"
    * Environments
        * New Environment 
            * Name: dev
            * Deployment branches and tags
                * Dropdown: Selected branches and tags
                * Add the branch "dev"
        * Environment Secret
            * AWS_ROLE_ARN: <AWS OIDC Role ARN>
        * Environment Variables
            * AWS_REGION: us-east-1 
            * TODO: Consider making this a secret.
    * Secrets & Variables
        * Actions
            * Repository Secrets
                * SWIFT_PACKAGE_MANAGER_PAT: <GitHub Token>

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
