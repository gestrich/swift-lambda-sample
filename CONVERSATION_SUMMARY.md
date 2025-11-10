# Swift Lambda Sample - Conversation Summary

## Overview
This document provides a comprehensive summary of the debugging and configuration session for the Swift Lambda Sample application, detailing the journey from initial setup to a fully functional API Gateway + Lambda + RDS PostgreSQL stack.

## Initial State
- Swift Lambda application with API Gateway integration
- CDK infrastructure in nested `cdk/` directory
- RDS PostgreSQL database backend
- GitHub Actions for automated deployments
- AWS profile: `production`

## Problems Encountered and Solutions

### 1. API Gateway Not Publicly Accessible

**Problem**: API Gateway was configured as PRIVATE endpoint, only accessible from within VPC.

**Error**: 403 Forbidden - "User: anonymous is not authorized to perform: execute-api:Invoke"

**Solution**:
- Changed endpoint type from `PRIVATE` to `REGIONAL` in `cdk/lib/constructs/api-gateway-construct.ts`
- Removed VPC endpoint infrastructure
- Removed restrictive resource policy
- Deployed with `cdk deploy --profile production`

**Files Modified**:
- `cdk/lib/constructs/api-gateway-construct.ts` - Changed endpoint configuration
- `cdk/lib/swift-lambda-stack.ts` - Removed VPC endpoint references

### 2. API Path Routing Failure

**Problem**: Lambda handler couldn't parse URL paths correctly, returning "Path Not Found: api"

**Root Cause**: The `leadingPathPart` was set to empty string, so paths like `/prod/api/database` weren't being parsed to extract the `/api` prefix.

**Solution**:
- Changed `leadingPathPart` from `""` to `"api"` in `Sources/SwiftLambda/APIGatewayHandler.swift:52`
- Committed and pushed to trigger GitHub Actions deployment

**Files Modified**:
- `Sources/SwiftLambda/APIGatewayHandler.swift`

### 3. Secrets Manager Access Denied

**Problem**: Lambda couldn't access hardcoded secret `mops/swift-lambda-sample/password`

**Root Cause**:
- Secret ID was hardcoded in ConfigurationService
- Actual RDS secret had different name: `DatabaseDbPassword2D27F983-rXdFpMxOgXEI`
- Lambda had permission but was looking for wrong secret

**Solution**:
- Made secret ID configurable via `POSTGRES_PASSWORD_SECRET_ID` environment variable
- Updated `ConfigurationService.swift` to read from environment with fallback
- Updated `lambda-construct.ts` to pass `props.dbSecret.secretName`
- Deployed via CDK and GitHub Actions

**Files Modified**:
- `Sources/SwiftServerApp/Configuration/ConfigurationService.swift:13-19`
- `cdk/lib/constructs/lambda-construct.ts:54`

### 4. PostgreSQL SSL/TLS Required

**Problem**: RDS rejecting connections - "no pg_hba.conf entry... no encryption"

**Root Cause**: AWS RDS requires SSL/TLS connections, but Swift code had SSL disabled

**Solution**:
- Added `import NIOSSL` to `UserStorePostgres.swift`
- Created SSL context: `NIOSSLContext(configuration: .clientDefault)`
- Changed TLS mode from `.disable` to `.prefer(sslContext)`
- Deployed via GitHub Actions

**Files Modified**:
- `Sources/SwiftServerApp/UserStore/UserStorePostgres.swift:12,32-33`

### 5. Password Authentication Failed

**Problem**: "password authentication failed for user 'docker'"

**Root Cause**: RDS secret is JSON object `{"password": "..."}` but code was using entire JSON string as password

**Solution**:
- Added JSON parsing in `ConfigurationService.swift` to extract password field
- Implemented fallback for plain string secrets (backwards compatibility)
- Deployed via GitHub Actions

**Files Modified**:
- `Sources/SwiftServerApp/Configuration/ConfigurationService.swift:62-72`

**Code Addition**:
```swift
// Parse the secret as JSON to extract the password
guard let secretData = secretString.data(using: .utf8),
      let secretJson = try? JSONSerialization.jsonObject(with: secretData) as? [String: Any],
      let databasePassword = secretJson["password"] as? String else {
    // Fallback: if secret is just a plain string, use it directly
    return PostgresConfiguration(..., userPassword: secretString)
}
```

### 6. Database Does Not Exist

**Problem**: "database 'swiftlambdasamplestack-databaseinstanceaa8a5fde-wmw0coj9qkzb' does not exist"

**Root Cause**: Lambda environment variable was using RDS instance identifier instead of actual database name

**Solution**:
- Changed `POSTGRES_DBNAME` from `props.database.instanceIdentifier` to `'FFMSampleLambdaDB'`
- Deployed via CDK

**Files Modified**:
- `cdk/lib/constructs/lambda-construct.ts:53`

## Deployment Workflow

### CDK Infrastructure Changes
```bash
cd cdk
cdk deploy --profile production
```

### Swift Code Changes
1. Commit changes to dev branch
2. Push to GitHub: `git push origin dev`
3. GitHub Actions automatically builds and deploys Lambda
4. Monitor with: `gh run watch` or `gh run list --limit 5`

## Final Working Configuration

### API Gateway
- Type: REGIONAL (public)
- URL: `https://gmyk36woqc.execute-api.us-east-1.amazonaws.com/prod/`
- Integration: Lambda Proxy

### Lambda Function
- Name: `swift-lambda-sample`
- Runtime: `PROVIDED_AL2` (Swift 6.2.0 custom runtime)
- Handler: `lambda_function.main`
- Memory: 512 MB
- Timeout: 30 seconds

### Environment Variables
```
POSTGRES_HOST: <RDS endpoint>
POSTGRES_PORT: 5432
POSTGRES_USER_NAME: docker
POSTGRES_DBNAME: FFMSampleLambdaDB
POSTGRES_PASSWORD_SECRET_ID: DatabaseDbPassword2D27F983-rXdFpMxOgXEI
SQS_URL: <queue URL>
S3_BUCKET_NAME: <bucket name>
```

### RDS PostgreSQL
- Engine: PostgreSQL 16
- Instance: db.t3.micro
- Database Name: `FFMSampleLambdaDB`
- SSL/TLS: Required
- Multi-AZ: Yes

## API Endpoints Tested

### Database Initialization
```bash
curl -X POST https://gmyk36woqc.execute-api.us-east-1.amazonaws.com/prod/api/database
```
Response: `"Database Initialized"`

### Create User
```bash
curl -X POST https://gmyk36woqc.execute-api.us-east-1.amazonaws.com/prod/api/users \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test123","firstName":"Test","lastName":"User"}'
```

### Get All Users
```bash
curl https://gmyk36woqc.execute-api.us-east-1.amazonaws.com/prod/api/users
```

## Key Learnings

1. **AWS RDS Secrets**: RDS-managed secrets are JSON objects, not plain strings. Always parse the JSON to extract the `password` field.

2. **RDS SSL/TLS**: AWS RDS requires SSL connections. Use `NIOSSL` and configure `.prefer(sslContext)` for PostgreSQL connections.

3. **Database Name vs Instance Identifier**: Don't confuse RDS instance identifier with database name. The database name is what you specify during creation (e.g., `FFMSampleLambdaDB`).

4. **API Gateway Endpoint Types**:
   - PRIVATE: VPC-only access, requires VPC endpoint
   - REGIONAL: Public internet access (suitable for demos)
   - EDGE: CloudFront distribution (global)

5. **Lambda Environment Variables**: Make configuration flexible by reading from environment variables rather than hardcoding values.

6. **GitHub Actions for Lambda**: Swift Lambda deployments work well with GitHub Actions. Changes to dev branch automatically trigger rebuilds.

## Files Modified Summary

### CDK Infrastructure (`cdk/`)
- `lib/constructs/api-gateway-construct.ts` - Changed to REGIONAL endpoint
- `lib/constructs/lambda-construct.ts` - Fixed environment variables
- `lib/swift-lambda-stack.ts` - Removed VPC endpoint

### Swift Application (`Sources/`)
- `SwiftLambda/APIGatewayHandler.swift` - Fixed path routing
- `SwiftServerApp/Configuration/ConfigurationService.swift` - Made secret configurable, added JSON parsing
- `SwiftServerApp/UserStore/UserStorePostgres.swift` - Enabled SSL/TLS

## Success Metrics

✅ API Gateway publicly accessible
✅ Database connection established with SSL/TLS
✅ Database initialized successfully
✅ User CRUD operations working
✅ All environment variables configured correctly
✅ GitHub Actions deployment pipeline functional
✅ Comprehensive documentation created (CLAUDE.md)

## Timeline

1. Initial exploration of codebase structure
2. Fixed API Gateway accessibility (PRIVATE → REGIONAL)
3. Fixed API path routing (`leadingPathPart = "api"`)
4. Fixed Secrets Manager access (environment variable)
5. Enabled SSL/TLS for PostgreSQL
6. Fixed password parsing (JSON secret)
7. Fixed database name (vs instance identifier)
8. Verified full CRUD functionality
9. Created documentation

## Total Deployment Cycles

- **CDK Deployments**: 3
- **GitHub Actions Deployments**: 4
- **Total Issues Resolved**: 6

## Monitoring Commands Reference

```bash
# Watch GitHub Actions run
gh run watch

# List recent runs
gh run list --limit 5

# View specific run
gh run view <run-id>

# Check CDK stack status
aws cloudformation describe-stacks \
  --stack-name SwiftLambdaSampleStack \
  --profile production

# Test API endpoint
curl https://gmyk36woqc.execute-api.us-east-1.amazonaws.com/prod/api/users
```

## Conclusion

The Swift Lambda Sample application is now fully operational with:
- Public API Gateway endpoint
- Secure PostgreSQL RDS connection with SSL/TLS
- Proper secret management via AWS Secrets Manager
- Automated deployment via GitHub Actions
- Complete CRUD functionality for user management

All infrastructure is defined as code in the nested `cdk/` directory, making it reproducible and maintainable. The application demonstrates best practices for serverless Swift applications on AWS.
