# CDK Migration Plan: Terraform to AWS CDK

**AWS Profile to use: `production`**

## Overview

This document outlines the plan to migrate the `swift-lambda-sample` infrastructure from Terraform/Terragrunt to AWS CDK (Cloud Development Kit) using TypeScript.

## ⚠️ IMPORTANT: Incremental Development & Verification

**After completing each major step below, you MUST:**

1. **Build**: `npm run build`
2. **Synthesize**: `cdk synth` - Verify CloudFormation template is valid
3. **Deploy**: `cdk deploy` - Deploy to AWS and verify resources created
4. **Test**: Verify the new resources work as expected
5. **Tear Down**: `cdk destroy` - Clean up to avoid costs
6. **Commit**: Commit working code to git before proceeding

This iterative approach ensures:
- ✅ Each component works independently before adding complexity
- ✅ Easy to identify which change broke something
- ✅ No accumulation of AWS charges during development
- ✅ Clean rollback points if needed

## Major Migration Steps

- [x] **Step 1**: Set up project structure, config, and VPC (networking foundation)
- [x] **Step 2**: Add S3 bucket and SQS queues (simple stateless resources)
- [x] **Step 3**: Add RDS Postgres database with Secrets Manager
- [x] **Step 4**: Add Lambda function with all integrations
- [x] **Step 5**: Add API Gateway and CloudWatch monitoring (complete the stack)

Each step builds on the previous one. **Do not skip the verification process between steps!**

## Current CDK Project Structure

The existing CDK project is a TypeScript-based sample with:
- **Framework**: AWS CDK v2.215.0
- **Language**: TypeScript 5.6.3
- **Sample Resources**: SNS Topic + SQS Queue
- **Entry Point**: `bin/cdk.ts`
- **Stack**: `lib/cdk-stack.ts`
- **Testing**: Jest with CDK assertions

## Target Infrastructure (from Terraform Module)

### Resources to Migrate
1. **VPC and Networking**
   - VPC with public and private subnets across 2+ AZs
   - Internet Gateway
   - NAT Gateway (for Lambda internet access)
   - Route tables and associations
   - VPC Endpoint for API Gateway

2. **Lambda Function**
   - Swift runtime (`provided.al2`)
   - VPC configuration
   - Environment variables (RDS, SQS, S3)
   - IAM execution role
   - Security groups

3. **API Gateway**
   - REST API (private)
   - VPC endpoint integration
   - OpenAPI specification
   - Resource policy
   - Deployment and stage

4. **RDS Postgres Database**
   - PostgreSQL 13.10
   - db.t3.micro instance
   - DB subnet group
   - Security groups
   - Master password from Secrets Manager

5. **SQS Queue**
   - Main queue
   - Dead Letter Queue (DLQ)
   - Lambda event source mapping

6. **S3 Bucket**
   - Data storage bucket
   - Versioning
   - Encryption

7. **Secrets Manager**
   - Postgres password secret
   - KMS encryption

8. **CloudWatch Events**
   - Scheduled event rule (cron)
   - Lambda target with custom payload

9. **IAM Roles and Policies**
   - Lambda execution role
   - API Gateway role
   - GitHub Actions OIDC role (optional)
   - S3, SQS, RDS, Secrets Manager permissions

## CDK Project Structure

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
├── tsconfig.json
└── README.md
```

## Migration Approach

### 1. Update Dependencies

Add required CDK construct libraries to `package.json`:

```json
{
  "dependencies": {
    "aws-cdk-lib": "2.215.0",
    "constructs": "^10.0.0"
  }
}
```

**CDK modules used** (all part of `aws-cdk-lib`):
- `aws-ec2` - VPC, subnets, security groups
- `aws-lambda` - Lambda functions
- `aws-apigateway` - API Gateway
- `aws-rds` - RDS database
- `aws-sqs` - SQS queues
- `aws-s3` - S3 buckets
- `aws-secretsmanager` - Secrets
- `aws-events` - CloudWatch Events
- `aws-events-targets` - Event targets
- `aws-iam` - IAM roles and policies
- `aws-logs` - CloudWatch Logs

### 2. Create L3 Constructs (Recommended Pattern)

Create reusable L3 constructs for each major component to promote:
- **Reusability**: Share across multiple stacks
- **Testability**: Test each construct independently
- **Separation of Concerns**: Each construct owns its domain
- **Type Safety**: Strong TypeScript typing

### 3. Configuration Management

Create environment-specific configuration files:

```typescript
// lib/config/types.ts
export interface SwiftLambdaConfig {
  environment: 'dev' | 'staging' | 'prod';
  vpc: {
    cidr: string;
    maxAzs: number;
    natGateways: number;
  };
  lambda: {
    memorySize: number;
    timeout: number;
    reservedConcurrentExecutions?: number;
  };
  database: {
    instanceType: string;
    allocatedStorage: number;
    backupRetention: number;
    multiAz: boolean;
  };
  monitoring: {
    scheduleExpression: string;
    releaseLookbackHours: number;
  };
  github?: {
    repository: string;
    oidcProviderArn: string;
  };
}

// lib/config/dev.ts
export const devConfig: SwiftLambdaConfig = {
  environment: 'dev',
  vpc: {
    cidr: '10.0.0.0/16',
    maxAzs: 2,
    natGateways: 1  // Single NAT Gateway for cost optimization
  },
  lambda: {
    memorySize: 10240,
    timeout: 900
  },
  database: {
    instanceType: 'db.t3.micro',
    allocatedStorage: 10,
    backupRetention: 1,
    multiAz: false  // Single AZ for dev
  },
  monitoring: {
    scheduleExpression: 'cron(0 6 * * ? *)',
    releaseLookbackHours: 2160
  }
};
```

### 4. Component-by-Component Migration

#### A. VPC Construct (`lib/constructs/vpc-construct.ts`)

```typescript
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';

export interface VpcConstructProps {
  cidr: string;
  maxAzs: number;
  natGateways: number;
}

export class VpcConstruct extends Construct {
  public readonly vpc: ec2.Vpc;

  constructor(scope: Construct, id: string, props: VpcConstructProps) {
    super(scope, id);

    this.vpc = new ec2.Vpc(this, 'Vpc', {
      ipAddresses: ec2.IpAddresses.cidr(props.cidr),
      maxAzs: props.maxAzs,
      natGateways: props.natGateways,
      subnetConfiguration: [
        {
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24
        },
        {
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24
        }
      ]
    });
  }
}
```

**Key Features**:
- Automatic subnet creation across AZs
- Public subnets for NAT Gateway
- Private subnets with egress (internet access via NAT)
- Route table configuration handled automatically
- Lambda can access internet and AWS services

#### B. Database Construct (`lib/constructs/database-construct.ts`)

```typescript
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { RemovalPolicy } from 'aws-cdk-lib';

export interface DatabaseConstructProps {
  vpc: ec2.IVpc;
  instanceType: string;
  allocatedStorage: number;
  backupRetention: number;
  multiAz: boolean;
  databaseName: string;
}

export class DatabaseConstruct extends Construct {
  public readonly instance: rds.DatabaseInstance;
  public readonly secret: secretsmanager.Secret;
  public readonly securityGroup: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props: DatabaseConstructProps) {
    super(scope, id);

    // Create secret for master password
    this.secret = new secretsmanager.Secret(this, 'DbPassword', {
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'docker' }),
        generateStringKey: 'password',
        excludePunctuation: true,
        passwordLength: 32
      }
    });

    // Security group for database
    this.securityGroup = new ec2.SecurityGroup(this, 'SecurityGroup', {
      vpc: props.vpc,
      description: 'RDS Security Group',
      allowAllOutbound: false
    });

    // RDS instance
    this.instance = new rds.DatabaseInstance(this, 'Instance', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_13_10
      }),
      instanceType: new ec2.InstanceType(props.instanceType),
      vpc: props.vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      securityGroups: [this.securityGroup],
      databaseName: props.databaseName,
      credentials: rds.Credentials.fromSecret(this.secret),
      allocatedStorage: props.allocatedStorage,
      backupRetention: Duration.days(props.backupRetention),
      multiAz: props.multiAz,
      removalPolicy: RemovalPolicy.DESTROY  // Use RETAIN for prod
    });
  }
}
```

**Key Features**:
- Automatic secret generation in Secrets Manager
- Credentials rotation support (can be enabled)
- Automatic backup configuration
- Security group with principle of least privilege

#### C. Queue Construct (`lib/constructs/queue-construct.ts`)

```typescript
import { Construct } from 'constructs';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import { Duration } from 'aws-cdk-lib';

export interface QueueConstructProps {
  visibilityTimeout: Duration;
  messageRetention: Duration;
  maxReceiveCount: number;
}

export class QueueConstruct extends Construct {
  public readonly queue: sqs.Queue;
  public readonly deadLetterQueue: sqs.Queue;

  constructor(scope: Construct, id: string, props: QueueConstructProps) {
    super(scope, id);

    // Dead Letter Queue
    this.deadLetterQueue = new sqs.Queue(this, 'DLQ', {
      queueName: 'swift-lambda-sample-dlq',
      retentionPeriod: Duration.hours(12),
      visibilityTimeout: Duration.hours(12)
    });

    // Main Queue
    this.queue = new sqs.Queue(this, 'Queue', {
      queueName: 'swift-lambda-sample',
      visibilityTimeout: props.visibilityTimeout,
      retentionPeriod: props.messageRetention,
      deadLetterQueue: {
        queue: this.deadLetterQueue,
        maxReceiveCount: props.maxReceiveCount
      }
    });
  }
}
```

#### D. Lambda Construct (`lib/constructs/lambda-construct.ts`)

```typescript
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { Duration } from 'aws-cdk-lib';
import { SqsEventSource } from 'aws-cdk-lib/aws-lambda-event-sources';

export interface LambdaConstructProps {
  vpc: ec2.IVpc;
  database: rds.DatabaseInstance;
  queue: sqs.Queue;
  dataBucket: s3.Bucket;
  dbSecret: secretsmanager.Secret;
  memorySize: number;
  timeout: number;
  reservedConcurrentExecutions?: number;
}

export class LambdaConstruct extends Construct {
  public readonly function: lambda.Function;
  public readonly securityGroup: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props: LambdaConstructProps) {
    super(scope, id);

    // Security group for Lambda
    this.securityGroup = new ec2.SecurityGroup(this, 'SecurityGroup', {
      vpc: props.vpc,
      description: 'Lambda VPC Security Group',
      allowAllOutbound: true
    });

    // Lambda function
    this.function = new lambda.Function(this, 'Function', {
      runtime: lambda.Runtime.PROVIDED_AL2,
      handler: 'lambda_function.main',
      code: lambda.Code.fromAsset('lambda_function_payload.zip'),
      vpc: props.vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      securityGroups: [this.securityGroup],
      memorySize: props.memorySize,
      timeout: Duration.seconds(props.timeout),
      reservedConcurrentExecutions: props.reservedConcurrentExecutions,
      environment: {
        POSTGRES_HOST: props.database.dbInstanceEndpointAddress,
        POSTGRES_PORT: props.database.dbInstanceEndpointPort,
        POSTGRES_USER_NAME: 'docker',
        POSTGRES_DBNAME: props.database.instanceIdentifier,
        SQS_URL: props.queue.queueUrl,
        S3_BUCKET_NAME: props.dataBucket.bucketName
      }
    });

    // Grant permissions
    props.dataBucket.grantReadWrite(this.function);
    props.queue.grantConsumeMessages(this.function);
    props.queue.grantSendMessages(this.function);
    props.dbSecret.grantRead(this.function);

    // Add SQS event source
    this.function.addEventSource(new SqsEventSource(props.queue, {
      batchSize: 1,
      enabled: true
    }));

    // Configure async invocation
    this.function.configureAsyncInvoke({
      maxEventAge: Duration.minutes(30),
      retryAttempts: 1
    });
  }
}
```

**Key Features**:
- Automatic IAM permission grants using `.grant*()` methods
- Built-in event source mapping for SQS
- Type-safe environment variable configuration
- Security group automatic management

#### E. API Gateway Construct (`lib/constructs/api-gateway-construct.ts`)

```typescript
import { Construct } from 'constructs';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import { readFileSync } from 'fs';
import { join } from 'path';

export interface ApiGatewayConstructProps {
  vpc: ec2.IVpc;
  lambdaFunction: lambda.Function;
  allowedCidrs?: string[];
}

export class ApiGatewayConstruct extends Construct {
  public readonly api: apigateway.RestApi;
  public readonly vpcEndpoint: ec2.InterfaceVpcEndpoint;

  constructor(scope: Construct, id: string, props: ApiGatewayConstructProps) {
    super(scope, id);

    // Security group for VPC endpoint
    const endpointSecurityGroup = new ec2.SecurityGroup(this, 'EndpointSg', {
      vpc: props.vpc,
      description: 'VPC Endpoint Security Group',
      allowAllOutbound: true
    });

    // Add ingress rules for allowed CIDRs
    (props.allowedCidrs || []).forEach((cidr, index) => {
      endpointSecurityGroup.addIngressRule(
        ec2.Peer.ipv4(cidr),
        ec2.Port.tcp(443),
        `Allow HTTPS from ${cidr}`
      );
    });

    // VPC Endpoint for API Gateway
    this.vpcEndpoint = new ec2.InterfaceVpcEndpoint(this, 'VpcEndpoint', {
      vpc: props.vpc,
      service: ec2.InterfaceVpcEndpointAwsService.APIGATEWAY,
      privateDnsEnabled: false,
      securityGroups: [endpointSecurityGroup],
      subnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS }
    });

    // Load OpenAPI spec
    const apiSpec = readFileSync(
      join(__dirname, '../../resources/api-gateway-spec.yaml'),
      'utf-8'
    );

    // Create REST API from OpenAPI spec
    this.api = new apigateway.SpecRestApi(this, 'Api', {
      apiDefinition: apigateway.ApiDefinition.fromInline(
        // Replace template variables
        JSON.parse(apiSpec
          .replace('${lambda_arn}', props.lambdaFunction.functionArn)
          .replace('${name}', 'Swift Lambda Sample API')
          .replace('${description}', 'Swift Lambda Sample API')
        )
      ),
      endpointConfiguration: {
        types: [apigateway.EndpointType.PRIVATE],
        vpcEndpoints: [this.vpcEndpoint]
      },
      policy: new iam.PolicyDocument({
        statements: [
          // Allow from VPC endpoint
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.AnyPrincipal()],
            actions: ['execute-api:Invoke'],
            resources: ['execute-api:/*']
          }),
          // Deny if not from VPC endpoint
          new iam.PolicyStatement({
            effect: iam.Effect.DENY,
            principals: [new iam.AnyPrincipal()],
            actions: ['execute-api:Invoke'],
            resources: ['execute-api:/*'],
            conditions: {
              StringNotEquals: {
                'aws:SourceVpce': this.vpcEndpoint.vpcEndpointId
              }
            }
          })
        ]
      })
    });

    // Grant Lambda invoke permission to API Gateway
    props.lambdaFunction.grantInvoke(new iam.ServicePrincipal('apigateway.amazonaws.com'));
  }
}
```

**Key Features**:
- Private API with VPC endpoint
- OpenAPI spec support
- Automatic resource policy configuration
- Security group management

#### F. Storage Construct (`lib/constructs/storage-construct.ts`)

```typescript
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { RemovalPolicy } from 'aws-cdk-lib';

export class StorageConstruct extends Construct {
  public readonly dataBucket: s3.Bucket;

  constructor(scope: Construct, id: string) {
    super(scope, id);

    this.dataBucket = new s3.Bucket(this, 'DataBucket', {
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.RETAIN  // Keep data on stack deletion
    });
  }
}
```

#### G. Monitoring Construct (`lib/constructs/monitoring-construct.ts`)

```typescript
import { Construct } from 'constructs';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as lambda from 'aws-cdk-lib/aws-lambda';

export interface MonitoringConstructProps {
  lambdaFunction: lambda.Function;
  scheduleExpression: string;
  appName: string;
  releaseLookbackHours: number;
}

export class MonitoringConstruct extends Construct {
  public readonly eventRule: events.Rule;

  constructor(scope: Construct, id: string, props: MonitoringConstructProps) {
    super(scope, id);

    this.eventRule = new events.Rule(this, 'ScheduleRule', {
      schedule: events.Schedule.expression(props.scheduleExpression),
      description: 'Stack Analytics Analysis trigger',
      targets: [
        new targets.LambdaFunction(props.lambdaFunction, {
          event: events.RuleTargetInput.fromObject({
            appName: props.appName,
            releaseLookbackHours: props.releaseLookbackHours
          })
        })
      ]
    });
  }
}
```

### 5. Main Stack (`lib/swift-lambda-stack.ts`)

```typescript
import { Stack, StackProps, Tags } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { SwiftLambdaConfig } from './config/types';
import { VpcConstruct } from './constructs/vpc-construct';
import { DatabaseConstruct } from './constructs/database-construct';
import { QueueConstruct } from './constructs/queue-construct';
import { StorageConstruct } from './constructs/storage-construct';
import { LambdaConstruct } from './constructs/lambda-construct';
import { ApiGatewayConstruct } from './constructs/api-gateway-construct';
import { MonitoringConstruct } from './constructs/monitoring-construct';

export interface SwiftLambdaStackProps extends StackProps {
  config: SwiftLambdaConfig;
}

export class SwiftLambdaStack extends Stack {
  constructor(scope: Construct, id: string, props: SwiftLambdaStackProps) {
    super(scope, id, props);

    const { config } = props;

    // VPC
    const vpc = new VpcConstruct(this, 'Vpc', {
      cidr: config.vpc.cidr,
      maxAzs: config.vpc.maxAzs,
      natGateways: config.vpc.natGateways
    });

    // Storage
    const storage = new StorageConstruct(this, 'Storage');

    // Database
    const database = new DatabaseConstruct(this, 'Database', {
      vpc: vpc.vpc,
      instanceType: config.database.instanceType,
      allocatedStorage: config.database.allocatedStorage,
      backupRetention: config.database.backupRetention,
      multiAz: config.database.multiAz,
      databaseName: 'FFMSampleLambdaDB'
    });

    // Queue
    const queue = new QueueConstruct(this, 'Queue', {
      visibilityTimeout: Duration.seconds(4500),
      messageRetention: Duration.days(1),
      maxReceiveCount: 5
    });

    // Lambda
    const lambda = new LambdaConstruct(this, 'Lambda', {
      vpc: vpc.vpc,
      database: database.instance,
      queue: queue.queue,
      dataBucket: storage.dataBucket,
      dbSecret: database.secret,
      memorySize: config.lambda.memorySize,
      timeout: config.lambda.timeout,
      reservedConcurrentExecutions: config.lambda.reservedConcurrentExecutions
    });

    // Allow Lambda to connect to database
    database.securityGroup.addIngressRule(
      lambda.securityGroup,
      ec2.Port.tcp(5432),
      'Allow Lambda to connect to database'
    );

    // API Gateway
    const apiGateway = new ApiGatewayConstruct(this, 'ApiGateway', {
      vpc: vpc.vpc,
      lambdaFunction: lambda.function,
      allowedCidrs: ['10.0.0.0/8']  // Configurable
    });

    // Monitoring
    const monitoring = new MonitoringConstruct(this, 'Monitoring', {
      lambdaFunction: lambda.function,
      scheduleExpression: config.monitoring.scheduleExpression,
      appName: 'Alpha',
      releaseLookbackHours: config.monitoring.releaseLookbackHours
    });

    // Add tags
    Tags.of(this).add('Environment', config.environment);
    Tags.of(this).add('Application', 'swift-lambda-sample');

    // Outputs
    new CfnOutput(this, 'VpcId', { value: vpc.vpc.vpcId });
    new CfnOutput(this, 'LambdaArn', { value: lambda.function.functionArn });
    new CfnOutput(this, 'ApiUrl', { value: apiGateway.api.url });
    new CfnOutput(this, 'BucketName', { value: storage.dataBucket.bucketName });
    new CfnOutput(this, 'QueueUrl', { value: queue.queue.queueUrl });
    new CfnOutput(this, 'DatabaseEndpoint', {
      value: database.instance.dbInstanceEndpointAddress
    });
  }
}
```

### 6. Update Entry Point (`bin/cdk.ts`)

```typescript
#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { SwiftLambdaStack } from '../lib/swift-lambda-stack';
import { devConfig } from '../lib/config/dev';

const app = new cdk.App();

new SwiftLambdaStack(app, 'SwiftLambdaSampleStack', {
  config: devConfig,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  description: 'Swift Lambda Sample infrastructure'
});

app.synth();
```

## Migration Benefits vs Terraform

### Advantages of CDK

1. **Type Safety**: Full TypeScript support with IDE autocomplete and compile-time checks
2. **Reusable Constructs**: Share components across stacks and projects
3. **Built-in Best Practices**: CDK L2/L3 constructs include AWS best practices by default
4. **Programmatic**: Use loops, conditions, functions - full programming language power
5. **Better Testing**: Unit test infrastructure code with Jest/CDK assertions
6. **Simplified IAM**: `.grant*()` methods automatically create minimal IAM policies
7. **Less Boilerplate**: CDK handles much more automatically (e.g., VPC subnets, route tables)
8. **CloudFormation Integration**: Full access to CloudFormation features when needed

### Example Comparisons

**Terraform (50+ lines)**:
```hcl
resource "aws_iam_role_policy_attachment" "s3_policy_attach" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

resource "aws_iam_policy" "s3_policy" {
  name_prefix = "${var.app_name}_"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
      Resource = "${data.aws_s3_bucket.stack_analytics_bucket.arn}*"
    }]
  })
}
```

**CDK (1 line)**:
```typescript
bucket.grantReadWrite(lambdaFunction);
```

## Testing Strategy

### Unit Tests

```typescript
// test/constructs/lambda-construct.test.ts
import { App, Stack } from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { LambdaConstruct } from '../../lib/constructs/lambda-construct';

test('Lambda function created with correct runtime', () => {
  const app = new App();
  const stack = new Stack(app, 'TestStack');

  // Create minimal props for testing
  const construct = new LambdaConstruct(stack, 'Lambda', {
    // ... props
  });

  const template = Template.fromStack(stack);

  template.hasResourceProperties('AWS::Lambda::Function', {
    Runtime: 'provided.al2',
    MemorySize: 10240,
    Timeout: 900
  });
});
```

### Integration Tests

```typescript
// test/swift-lambda-stack.test.ts
test('Stack creates all required resources', () => {
  const app = new App();
  const stack = new SwiftLambdaStack(app, 'TestStack', {
    config: devConfig
  });

  const template = Template.fromStack(stack);

  // Verify resource counts
  template.resourceCountIs('AWS::EC2::VPC', 1);
  template.resourceCountIs('AWS::Lambda::Function', 1);
  template.resourceCountIs('AWS::RDS::DBInstance', 1);
  template.resourceCountIs('AWS::SQS::Queue', 2);  // Main + DLQ
  template.resourceCountIs('AWS::S3::Bucket', 1);
  template.resourceCountIs('AWS::ApiGateway::RestApi', 1);
});
```

## Deployment Steps

### 1. Install Dependencies
```bash
cd cdk
npm install
```

### 2. Build TypeScript
```bash
npm run build
```

### 3. Bootstrap CDK (first time only)
```bash
cdk bootstrap
```

### 4. Synthesize CloudFormation
```bash
cdk synth
```

### 5. Deploy
```bash
cdk deploy
```

### 6. Destroy (cleanup)
```bash
cdk destroy
```

## Cost Considerations

Resources and estimated costs:
- **VPC**: Free (base) + NAT Gateway ~$32/month + data transfer
- **Lambda**: Pay per invocation + compute time (~$0 for low usage)
- **RDS**: db.t3.micro ~$15/month (single-AZ for dev)
- **API Gateway**: Pay per request (~$0 for low usage)
- **S3**: Pay per storage + requests (~$0.023/GB)
- **SQS**: Free tier covers most use cases

**Monthly Cost Estimate (Dev Environment)**:
- ~$47-52/month (NAT Gateway: ~$32, RDS: ~$15)

**Cost Optimizations Applied**:
- ✅ Single NAT Gateway instead of multi-AZ (saves ~$32/month per additional AZ)
- ✅ Single-AZ RDS (saves ~50% on RDS costs)
- ✅ Lower backup retention periods

**Additional Cost Savings** (if Lambda doesn't need internet):
- Remove NAT Gateway entirely (save $32/month)
- Use VPC endpoints for specific AWS services instead

## Migration Checklist

- [ ] Create constructs for each component
- [ ] Create configuration files (dev, prod)
- [ ] Copy OpenAPI spec to `resources/`
- [ ] Update main stack to wire everything together
- [ ] Update bin/cdk.ts entry point
- [ ] Write unit tests for constructs
- [ ] Write integration tests for stack
- [ ] Update README with deployment instructions
- [ ] Test `cdk synth` - verify CloudFormation template
- [ ] Test `cdk deploy` in dev account
- [ ] Verify all resources created correctly
- [ ] Test Lambda, API Gateway, RDS connectivity
- [ ] Document differences from Terraform implementation
- [ ] Add GitHub Actions workflow for CI/CD (optional)

## Summary

This CDK migration provides:
- ✅ **Type-safe infrastructure as code** with TypeScript
- ✅ **Reusable constructs** for better organization
- ✅ **Automatic best practices** built into L2/L3 constructs
- ✅ **Simpler IAM management** with grant methods
- ✅ **Better testing** with CDK assertions
- ✅ **All resources from Terraform** - VPC, Lambda, RDS, API Gateway, SQS, S3
- ✅ **Environment-specific configurations** for dev/prod
- ✅ **Reduced boilerplate** compared to Terraform
- ✅ **Full CloudFormation power** when needed

The result is a more maintainable, testable, and type-safe infrastructure codebase that's easier to extend and modify than Terraform.
