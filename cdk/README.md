# Swift Lambda Sample - AWS CDK Infrastructure

AWS CDK infrastructure for the Swift Lambda Sample application, providing a complete serverless architecture with VPC networking, API Gateway, Lambda, RDS Postgres, SQS, and S3.

## Architecture Overview

This CDK application deploys a complete AWS infrastructure stack with the following components:

- **VPC Networking**: Multi-AZ VPC with public and private subnets, NAT Gateway for internet access
- **Lambda Function**: Swift-based Lambda with VPC integration and event-driven processing
- **API Gateway**: Private REST API with VPC endpoint integration
- **RDS Postgres**: Database with automated backups and Secrets Manager integration
- **SQS Queues**: Message processing with Dead Letter Queue support
- **S3 Storage**: Encrypted, versioned data bucket
- **CloudWatch Events**: Scheduled Lambda invocations
- **IAM**: Least-privilege security with automatic permission management

## Features

### Networking & Security
- Multi-AZ VPC with configurable CIDR ranges
- Private and public subnet configurations
- NAT Gateway for Lambda internet access
- VPC endpoints for private API Gateway access
- Security groups with principle of least privilege
- Encrypted data at rest (S3, RDS)

### Compute & Processing
- Swift Lambda runtime (`provided.al2023`)
- Configurable memory (up to 10GB) and timeout settings
- SQS event source mapping for message processing
- Async invocation configuration with retry logic
- Reserved concurrency support
- VPC integration for secure database access

### API & Integration
- Private API Gateway with VPC endpoint
- OpenAPI specification support
- Resource policy for VPC-only access
- Lambda proxy integration

### Database
- PostgreSQL 13.10 on RDS
- Automated backups with configurable retention
- Master credentials in Secrets Manager
- Multi-AZ support for production
- Security group isolation

### Monitoring & Scheduling
- CloudWatch Events for scheduled Lambda invocations
- Custom event payloads
- Configurable cron expressions

### Configuration Management
- Environment-specific configurations (dev, prod)
- Type-safe configuration with TypeScript interfaces
- Modular L3 constructs for reusability

## Project Structure

```
cdk/
├── bin/
│   └── cdk.ts                           # App entry point
├── lib/
│   ├── swift-lambda-stack.ts           # Main stack
│   ├── constructs/
│   │   ├── vpc-construct.ts            # VPC and networking
│   │   ├── lambda-construct.ts         # Lambda function and IAM
│   │   ├── api-gateway-construct.ts    # API Gateway
│   │   ├── database-construct.ts       # RDS Postgres
│   │   ├── queue-construct.ts          # SQS queues
│   │   ├── storage-construct.ts        # S3 bucket
│   │   └── monitoring-construct.ts     # CloudWatch events
│   └── config/
│       ├── dev.ts                      # Dev environment config
│       ├── prod.ts                     # Prod environment config
│       └── types.ts                    # TypeScript interfaces
├── resources/
│   └── api-gateway-spec.yaml           # OpenAPI spec
├── test/
│   ├── swift-lambda-stack.test.ts      # Stack tests
│   └── constructs/                     # Construct tests
├── cdk.json
├── package.json
└── tsconfig.json
```

## Prerequisites

- Node.js 18.x or later
- AWS CLI configured with appropriate credentials
- AWS CDK CLI: `npm install -g aws-cdk`
- AWS account bootstrapped for CDK: `cdk bootstrap`

## Getting Started

### Installation

```bash
cd cdk
npm install
```

### Build

```bash
npm run build
```

### Synthesize CloudFormation Template

```bash
cdk synth
```

This generates the CloudFormation template and allows you to review what will be deployed.

### Deploy

```bash
cdk deploy
```

The deployment will:
1. Create VPC and networking infrastructure
2. Set up RDS database with secure credentials
3. Create SQS queues
4. Deploy S3 bucket
5. Deploy Lambda function
6. Configure API Gateway with VPC endpoint
7. Set up CloudWatch Events

### Destroy

To remove all resources:

```bash
cdk destroy --profile production
```

**Note**: S3 bucket has `RETAIN` removal policy and will not be deleted automatically.

#### Troubleshooting Destroy Failures

If `cdk destroy` fails with errors about security groups or subnets having dependencies, this is likely due to orphaned Lambda ENIs (Elastic Network Interfaces) that weren't cleaned up automatically.

**Common error messages:**
- `resource sg-XXXXXXX has a dependent object`
- `The subnet 'subnet-XXXXXXX' has dependencies and cannot be deleted`

**Solution:**

1. Find orphaned ENIs in your security group:
   ```bash
   # Replace sg-XXXXXXX with the security group ID from the error
   aws ec2 describe-network-interfaces \
     --filters "Name=group-id,Values=sg-XXXXXXX" \
     --profile production \
     --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Description]' \
     --output table
   ```

2. Delete the orphaned ENIs:
   ```bash
   # For each ENI found (typically 2 for Lambda in VPC)
   aws ec2 delete-network-interface \
     --network-interface-id eni-XXXXXXX \
     --profile production
   ```

3. Retry the destroy command:
   ```bash
   cdk destroy --profile production --force
   ```

**Why this happens**: Lambda functions in VPCs create ENIs that can sometimes remain in "available" status after the Lambda is deleted, preventing VPC resources (security groups, subnets) from being removed.

#### Orphaned CloudWatch Log Groups

If `cdk deploy` fails with an error like:
```
Resource of type 'AWS::Logs::LogGroup' with identifier '/aws/lambda/swift-lambda-sample' already exists.
```

This means a log group from a previous deployment wasn't cleaned up. To fix:

```bash
# List log groups
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/lambda/swift-lambda-sample" \
  --profile production

# Delete the orphaned log group
aws logs delete-log-group \
  --log-group-name "/aws/lambda/swift-lambda-sample" \
  --profile production
```

**Note**: The Lambda construct now creates log groups with `RemovalPolicy.DESTROY` to prevent this issue in future deployments.

## Configuration

### Deployment Modes

The infrastructure supports **three deployment modes** with different cost and functionality trade-offs:

| Mode | Lambda | Database | VPC/NAT | Monthly Cost* | Use Case |
|------|--------|----------|---------|---------------|----------|
| **Minimal Cost** | Public (AWS-managed VPC) | None | ❌ | ~$0 | S3-only features, cost optimization |
| **Public Database** | Public (AWS-managed VPC) | Public RDS | ❌ | ~$15-30 | Database + S3 features, moderate cost |
| **Private (Full)** | Private VPC | Private RDS | ✅ | ~$47-62 | Full isolation, production-ready |

*Costs exclude Lambda invocations, S3 storage, and SQS usage (pay-per-use)

### Configuration Examples

Configurations are managed in `lib/config/dev.ts`:

#### **Minimal Cost Mode** (Default - Currently Active)

No VPC, no NAT Gateway, no database. Perfect for cost optimization and S3-only features.

```typescript
export const devConfig: SwiftLambdaConfig = {
  environment: 'dev',

  networking: {
    lambdaMode: 'public'  // Lambda runs in AWS-managed VPC (no cost)
  },

  lambda: {
    memorySize: 10240,
    timeout: 900
  },

  database: {
    mode: 'none'  // No database created
  },

  monitoring: {
    scheduleExpression: 'cron(0 6 * * ? *)',
    releaseLookbackHours: 2160
  }
};
```

**What works:**
- ✅ `/api/file` - S3 upload/download
- ❌ `/api/users/*` - Returns "Database not configured" error
- ❌ `/api/database` - Returns "Database not configured" error

---

#### **Public Database Mode**

Database accessible from internet (with security group restrictions). Lambda in AWS-managed VPC.

```typescript
export const devConfig: SwiftLambdaConfig = {
  environment: 'dev',

  networking: {
    lambdaMode: 'public'  // No VPC created
  },

  lambda: {
    memorySize: 10240,
    timeout: 900
  },

  database: {
    mode: 'public',  // RDS publicly accessible
    instanceType: 't3.micro',
    allocatedStorage: 10,
    backupRetention: 1,
    multiAz: false
  },

  monitoring: {
    scheduleExpression: 'cron(0 6 * * ? *)',
    releaseLookbackHours: 2160
  }
};
```

**What works:**
- ✅ All endpoints work
- ⚠️ Database accessible from internet (secured by security groups and credentials)

---

#### **Private Mode** (Full Isolation)

Lambda and database in private VPC with NAT Gateway for internet access.

```typescript
export const devConfig: SwiftLambdaConfig = {
  environment: 'dev',

  networking: {
    lambdaMode: 'private',
    vpc: {
      cidr: '10.0.0.0/16',
      maxAzs: 2,
      natGateways: 1
    }
  },

  lambda: {
    memorySize: 10240,
    timeout: 900
  },

  database: {
    mode: 'private',  // Database in private subnet
    instanceType: 't3.micro',
    allocatedStorage: 10,
    backupRetention: 1,
    multiAz: false
  },

  monitoring: {
    scheduleExpression: 'cron(0 6 * * ? *)',
    releaseLookbackHours: 2160
  }
};
```

**What works:**
- ✅ All endpoints work
- ✅ Full network isolation
- ✅ Production-ready security

---

### Configuration Rules

The stack validates configurations and enforces these rules:

1. ✅ **Valid**: `lambdaMode: 'public'` + `database.mode: 'none'` (minimal cost)
2. ✅ **Valid**: `lambdaMode: 'public'` + `database.mode: 'public'` (public database)
3. ❌ **Invalid**: `lambdaMode: 'public'` + `database.mode: 'private'` (private DB needs VPC)
4. ✅ **Valid**: `lambdaMode: 'private'` + `database.mode: 'none'` (VPC but no DB)
5. ✅ **Valid**: `lambdaMode: 'private'` + `database.mode: 'public'` (VPC + public DB)
6. ✅ **Valid**: `lambdaMode: 'private'` + `database.mode: 'private'` (full private)

---

### Switching Between Modes

1. **Edit** `lib/config/dev.ts` to use desired configuration
2. **Build**: `npm run build`
3. **Deploy**: `cdk deploy --profile production`

The deployment will automatically:
- ✅ Create resources that don't exist
- ✅ Delete resources no longer needed
- ✅ Update Lambda environment variables

**Example: Switching from Minimal Cost to Private Mode**

```typescript
// Before (minimal cost)
networking: { lambdaMode: 'public' },
database: { mode: 'none' }

// After (private mode)
networking: {
  lambdaMode: 'private',
  vpc: { cidr: '10.0.0.0/16', maxAzs: 2, natGateways: 1 }
},
database: {
  mode: 'private',
  instanceType: 't3.micro',
  allocatedStorage: 10,
  backupRetention: 1,
  multiAz: false
}
```

Then deploy:
```bash
npm run build
cdk deploy --profile production
```

---

### Using Different Environments

Modify `bin/cdk.ts` to use different configurations:

```typescript
import { prodConfig } from '../lib/config/prod';

new SwiftLambdaStack(app, 'SwiftLambdaSampleStack', {
  config: prodConfig,  // Use prod config
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  }
});
```

## Testing

### Run Tests

```bash
npm test
```

### Unit Tests

Tests are located in `test/` and use CDK assertions:

```typescript
test('Lambda function created with correct runtime', () => {
  const template = Template.fromStack(stack);

  template.hasResourceProperties('AWS::Lambda::Function', {
    Runtime: 'provided.al2023',
    MemorySize: 10240,
    Timeout: 900
  });
});
```

### Integration Tests

Full stack tests verify all resources are created:

```typescript
test('Stack creates all required resources', () => {
  const template = Template.fromStack(stack);

  template.resourceCountIs('AWS::EC2::VPC', 1);
  template.resourceCountIs('AWS::Lambda::Function', 1);
  template.resourceCountIs('AWS::RDS::DBInstance', 1);
  template.resourceCountIs('AWS::SQS::Queue', 2);  // Main + DLQ
  template.resourceCountIs('AWS::S3::Bucket', 1);
  template.resourceCountIs('AWS::ApiGateway::RestApi', 1);
});
```

## Stack Outputs

After deployment, the following outputs are available:

- `VpcId`: VPC identifier
- `LambdaArn`: Lambda function ARN
- `ApiUrl`: API Gateway URL
- `BucketName`: S3 bucket name
- `QueueUrl`: SQS queue URL
- `DatabaseEndpoint`: RDS endpoint address

Access outputs:

```bash
aws cloudformation describe-stacks --stack-name SwiftLambdaSampleStack --query 'Stacks[0].Outputs'
```

## IAM Permissions

The CDK app automatically creates minimal IAM policies using grant methods:

- Lambda can read/write to S3 bucket
- Lambda can send/receive SQS messages
- Lambda can read database credentials from Secrets Manager
- API Gateway can invoke Lambda
- CloudWatch Events can invoke Lambda

## Cost Estimation

### By Deployment Mode

| Resource | Minimal Cost | Public Database | Private (Full) |
|----------|--------------|-----------------|----------------|
| NAT Gateway | ❌ $0 | ❌ $0 | ✅ ~$32/month |
| RDS t3.micro (single-AZ) | ❌ $0 | ✅ ~$15-30/month | ✅ ~$15-30/month |
| Lambda | Pay per use (~$0 for low traffic) | Pay per use (~$0 for low traffic) | Pay per use (~$0 for low traffic) |
| API Gateway | Pay per request (~$0 for low traffic) | Pay per request (~$0 for low traffic) | Pay per request (~$0 for low traffic) |
| S3 | ~$0.023/GB + requests | ~$0.023/GB + requests | ~$0.023/GB + requests |
| SQS | Free tier covers most use cases | Free tier covers most use cases | Free tier covers most use cases |
| **Monthly Total** | **~$0** 💰 | **~$15-30** | **~$47-62** |

*Costs exclude Lambda invocations, S3 storage, and SQS message usage (pay-per-use)*

### Cost Optimizations

**Minimal Cost Mode** (~$0/month):
- No VPC or NAT Gateway
- No database
- Lambda in AWS-managed VPC (free)
- Perfect for S3-only workloads or testing

**Public Database Mode** (~$15-30/month):
- No VPC or NAT Gateway
- Public RDS (with security groups)
- Lambda in AWS-managed VPC (free)
- Good balance of features and cost

**Private Mode Optimizations**:
- Single NAT Gateway (vs multi-AZ: ~$64/month)
- Single-AZ RDS (vs multi-AZ: ~$30/month)
- Lower backup retention periods
- Smaller instance types (t3.micro vs larger)

**Production Considerations**:
- Multi-AZ NAT Gateways for high availability (~$32/month per AZ = ~$64/month)
- Multi-AZ RDS for database redundancy (~$60+/month)
- Longer backup retention (7-30 days)
- Reserved capacity for predictable workloads
- Larger instance types for performance

## CDK Benefits

This CDK implementation provides:

- **Type Safety**: Full TypeScript support with IDE autocomplete
- **Reusable Constructs**: Modular components shared across stacks
- **Built-in Best Practices**: AWS best practices by default
- **Simplified IAM**: `.grant*()` methods create minimal policies automatically
- **Less Boilerplate**: CDK handles VPC subnets, route tables, etc. automatically
- **Better Testing**: Unit test infrastructure with Jest
- **Programmatic**: Use loops, conditions, functions - full language power

### Example: IAM Permissions

Traditional approach (50+ lines):
```hcl
resource "aws_iam_policy" "s3_policy" {
  policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Action = ["s3:PutObject", "s3:GetObject"]
      Resource = "${aws_s3_bucket.data.arn}/*"
    }]
  })
}
```

CDK approach (1 line):
```typescript
bucket.grantReadWrite(lambdaFunction);
```

## Troubleshooting

### Deployment Fails

1. Verify AWS credentials: `aws sts get-caller-identity`
2. Check CDK is bootstrapped: `cdk bootstrap`
3. Review CloudFormation events: `aws cloudformation describe-stack-events --stack-name SwiftLambdaSampleStack`

### Lambda Can't Connect to RDS

- Verify Lambda and RDS are in the same VPC
- Check security group allows inbound on port 5432 from Lambda security group
- Verify Lambda is in private subnet with NAT Gateway access

### API Gateway Returns 403

- Verify request is coming from VPC or allowed CIDR ranges
- Check API Gateway resource policy
- Verify VPC endpoint is configured correctly

## Development Workflow

1. Make changes to constructs or configuration
2. Build: `npm run build`
3. Test: `npm test`
4. Synthesize: `cdk synth` (review CloudFormation)
5. Deploy: `cdk deploy`
6. Verify resources work as expected
7. Commit changes to git

## Contributing

When adding new infrastructure:

1. Create a new construct in `lib/constructs/`
2. Add configuration in `lib/config/types.ts`
3. Wire construct in `lib/swift-lambda-stack.ts`
4. Write tests in `test/constructs/`
5. Update this README

## Useful Commands

* `npm run build`   - Compile TypeScript to JavaScript
* `npm run watch`   - Watch for changes and compile
* `npm run test`    - Perform Jest unit tests
* `cdk deploy`      - Deploy this stack to your AWS account/region
* `cdk diff`        - Compare deployed stack with current state
* `cdk synth`       - Emit the synthesized CloudFormation template
* `cdk destroy`     - Remove all resources from AWS
