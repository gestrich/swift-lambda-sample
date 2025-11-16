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

### Quick Start

Deploy with minimal AWS costs (no database, no NAT Gateway):

```bash
# Initial deployment
swift run SwiftDeploy fresh-deploy
```

### Deployment Commands

| Command | Description |
|---------|-------------|
| `swift run SwiftDeploy fresh-deploy` | Initial deployment: CDK infrastructure + Lambda code |
| `swift run SwiftDeploy deploy` | Update CDK infrastructure only |
| `swift run SwiftDeploy update-lambda` | Update Lambda code only |
| `swift run SwiftDeploy status` | Check deployment status and outputs |
| `swift run SwiftDeploy tear-down` | Destroy all infrastructure |

### Deployment Options

Control costs by choosing which resources to deploy:

```bash
# Minimal deployment (default: no Postgres, no NAT Gateway)
swift run SwiftDeploy fresh-deploy

# Include PostgreSQL database (~$15/month)
swift run SwiftDeploy fresh-deploy --with-postgres

# Full deployment with PostgreSQL and NAT Gateway (~$47/month)
swift run SwiftDeploy fresh-deploy --with-postgres --with-nat-gateway
```

### Using tools.sh Wrapper

For convenience, use the `tools.sh` wrapper functions:

```bash
# Deployment
./tools.sh freshDeploy                                    # Initial deployment
./tools.sh freshDeploy --with-postgres                    # With database
./tools.sh deploy                                         # Update infrastructure
./tools.sh updateLambda                                   # Update Lambda code
./tools.sh deployStatus                                   # Check status
./tools.sh deployTearDown                                 # Destroy everything

# Testing
./tools.sh testDeployment                                 # Run all tests
./tools.sh testApiFile                                    # Test S3 endpoint
./tools.sh checkLambdaLogs                                # View logs
```

### Typical Workflows

**Initial Setup:**
```bash
./tools.sh freshDeploy
./tools.sh testDeployment
```

**Update Lambda Code:**
```bash
# Make changes to Swift code
vim Sources/SwiftLambda/APIGatewayHandler.swift

# Commit and deploy
git add -A && git commit -m "Update handler"
./tools.sh updateLambda
```

**Update Infrastructure:**
```bash
# Modify CDK code
vim cdk/lib/constructs/lambda-construct.ts

# Deploy infrastructure changes
./tools.sh deploy
```

For detailed deployment documentation, see [CLAUDE.md](CLAUDE.md).

## Getting Started

Begin by running the Lambda locally to familiarize yourself with the local development environment. Docker is utilized for running services locally.

1. **Configuration File**: Copy the JSON configuration for local services.
    - `./tools.sh copyConfig`
2. **Xcode Configuration**: 
    - Set environment variables in Xcode:
        - `LOCAL_LAMBDA_SERVER_ENABLED: true`
        - `MOCK_AWS_CREDENTIALS: true`
3. **Docker Desktop**: Install and start Docker Desktop.
    - [Mac Installation Guide](https://docs.docker.com/desktop/install/mac-install).
    - Open Docker Desktop (to run Docker server)
4. **Run Local Services**: Start local versions of Postgres and S3.
    - `./tools.sh startServices` command.
5. **Run Xcode**: Choose the "SwiftLambda" target -> "My Mac" -> Run button.
6. **Trigger API**: Use Postman to store and execute API calls.
    - Download from [Postman](https://www.postman.com/downloads).
    - TODO: Need to share some sample calls or even the full collection.
    
## Locally Access AWS Resources

While running your services locally is the preferred method of development, there will be cases you may need to connect your locally running lambda to AWS remote services.

1. **AWS Authentication Setup**: Your local machine needs access to your AWS account. These instructions are outside the scope of this document and may vary by your employer. Consider following the [AWS Command Line Interface Guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html) which will also explain how to authenticate.
2. **Configuration Update**: Adjust `~/.swiftSampleDemo/swiftLambdaDemo.json` with your AWS service parameters.
4. **Run Xcode**: Run the SwiftLambda target in Xcode.

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

- [CLAUDE.md](CLAUDE.md) - Detailed deployment and AWS operations guide
- [PRINCIPLES.md](docs/PRINCIPLES.md) - Server development principles and best practices
- [TODO.md](docs/TODO.md) - Project roadmap and planned improvements
