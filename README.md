# Swift Lambda Sample

## Summary

This repository offers a sample AWS Lambda, written in Swift. The aim is to provide a solid foundation that adheres to good server development practices. This is an open work-in-progress.

## Server Principles

### CI / CD

| State | Principle | Details |
|:---:|---|---|
|❌| Published Documentation | Explore GitHub actions for the [Open API Generator](https://www.swift.org/blog/introducing-swift-openapi-generator) and [DocC](https://developer.apple.com/documentation/docc). Publish as GitHub pages. |
|✅| Automatic Builds | Using GitHub Actions |
|✅| Automatic Tests | Using GitHub Actions |
|✅| Automatic Deploys | Using GitHub Actions |
|❌| Dev Staging Environment | Explore terraform workspaces |
|❌| CI/CD Failure Alerts | Explore GitHub email/Slack alerting |
|❌| Dependency Version Reporting | Explore GitHub Dependabot |

### Local Development

| State | Principle | Details |
|:---:|---|---|
|⚠️| Local Dev Environment | Local Docker containers to run local services (S3, DynamoDB, Postgres, etc.). Forming API GW bodies is tricky. Using Postman is useful but I'd like things to be accessible without a 3rd party tool (i.e., Command line app may be best). |
|⚠️| Trigger Remote APIs Locally | Lambdas can be triggered from the AWS CLI with proper permissions. API GW can be hit as REST endpoints. Consider using the [Open API Generator](https://www.swift.org/blog/introducing-swift-openapi-generator) and [DocC](https://developer.apple.com/documentation/docc) to create a client API GW that runs as a local command line tool. |
|✅| Select Local Dependencies | Use local Swift Package dependencies by providing a local package path in Package.swift. |
|✅| Unit Tests Have No Environment Restrictions | Dependency injection is used to hide AWS services from testable code. |
|⚠️| Dev Environment Documentation | This README has most relevant documentation but it needs improvement. |
|❌| Option to Build Product Locally | Need instructions for how to build the Docker image locally and how to log in to the Docker container for troubleshooting. |

### Production Monitoring

| State | Principle | Details |
|:---:|---|---|
|⚠️| Remote Logs | CloudWatch is used for logging. The search capabilities are not ideal though. |
|❌| Failure Alerts | Use CloudWatch Alarms. Need to show the error in the alert somehow. Also, need to support crash logs. |
|❌| Remote Performance | Look into CloudWatch. |

### Security 

| State | Principle | Details |
|:---:|---|---|
|✅| No secrets in the repository | AWS Secrets Manager is used to store any required secrets. |
|⚠️| No plain-text secrets in server logs | This needs to be audited. Look at the security of environment variables and what is in build logs. |

## Features

* **API Gateway**: Leverage Amazon's service for creating HTTP/S APIs.
* **CI/CD**: Automated testing, building, and deployment of your lambda to AWS using GitHub Actions.
* **RDS**: Utilize Amazon's managed database services, specifically Postgres in this example, including sample CRUD operations.
* **S3**: Basic operations demonstrated, including file upload and download.
* **Secrets Manager**: Secure retrieval of service secrets from AWS.

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
        * Create New 
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
