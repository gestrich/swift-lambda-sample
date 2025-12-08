# Server Development Principles

This document outlines the server development principles and best practices followed by this project. These principles guide decision-making and ensure the application maintains high standards for reliability, maintainability, and developer experience.

## CI / CD

| State | Principle | Details |
|:---:|---|---|
|❌| Published Documentation | Explore GitHub actions for the [Open API Generator](https://www.swift.org/blog/introducing-swift-openapi-generator) and [DocC](https://developer.apple.com/documentation/docc). Publish as GitHub pages. |
|✅| Automatic Builds | Using GitHub Actions |
|✅| Automatic Tests | Using GitHub Actions |
|✅| Automatic Deploys | Using GitHub Actions |
|❌| Dev Staging Environment | Explore terraform workspaces |
|❌| CI/CD Failure Alerts | Explore GitHub email/Slack alerting |
|❌| Dependency Version Reporting | Explore GitHub Dependabot |

## Local Development

| State | Principle | Details |
|:---:|---|---|
|⚠️| Local Dev Environment | Local Docker containers to run local services (S3, DynamoDB, Postgres, etc.). Forming API GW bodies is tricky. Using Postman is useful but I'd like things to be accessible without a 3rd party tool (i.e., Command line app may be best). |
|⚠️| Trigger Remote APIs Locally | Lambdas can be triggered from the AWS CLI with proper permissions. API GW can be hit as REST endpoints. Consider using the [Open API Generator](https://www.swift.org/blog/introducing-swift-openapi-generator) and [DocC](https://developer.apple.com/documentation/docc) to create a client API GW that runs as a local command line tool. |
|✅| Select Local Dependencies | Use local Swift Package dependencies by providing a local package path in Package.swift. |
|✅| Unit Tests Have No Environment Restrictions | Dependency injection is used to hide AWS services from testable code. |
|⚠️| Dev Environment Documentation | This README has most relevant documentation but it needs improvement. |
|❌| Option to Build Product Locally | Need instructions for how to build the Docker image locally and how to log in to the Docker container for troubleshooting. |

## Production Monitoring

| State | Principle | Details |
|:---:|---|---|
|⚠️| Remote Logs | CloudWatch is used for logging. The search capabilities are not ideal though. |
|❌| Failure Alerts | Use CloudWatch Alarms. Need to show the error in the alert somehow. Also, need to support crash logs. |
|❌| Remote Performance | Look into CloudWatch. |

## Security

| State | Principle | Details |
|:---:|---|---|
|✅| No secrets in the repository | AWS Secrets Manager is used to store any required secrets. |
|⚠️| No plain-text secrets in server logs | This needs to be audited. Look at the security of environment variables and what is in build logs. |

## Legend

- ✅ **Implemented** - Principle is fully implemented and working
- ⚠️ **Partial** - Principle is partially implemented or needs improvement
- ❌ **Not Implemented** - Principle is not yet implemented
