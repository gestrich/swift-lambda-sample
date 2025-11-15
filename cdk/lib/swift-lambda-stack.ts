import { Stack, StackProps, Tags, CfnOutput, Duration } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { SwiftLambdaConfig } from './config/types';
import { VpcConstruct } from './constructs/vpc-construct';
import { StorageConstruct } from './constructs/storage-construct';
import { QueueConstruct } from './constructs/queue-construct';
import { DatabaseConstruct } from './constructs/database-construct';
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

    // Validate configuration
    this.validateConfig(config);

    // VPC - Phase 1 (only if Lambda is in private mode)
    let vpc: VpcConstruct | undefined;
    if (config.networking.lambdaMode === 'private') {
      if (!config.networking.vpc) {
        throw new Error('VPC configuration is required when lambdaMode is "private"');
      }
      vpc = new VpcConstruct(this, 'Vpc', {
        cidr: config.networking.vpc.cidr,
        maxAzs: config.networking.vpc.maxAzs,
        natGateways: config.networking.vpc.natGateways
      });
    }

    // Storage - Phase 2
    const storage = new StorageConstruct(this, 'Storage');

    // Queue - Phase 2
    const queue = new QueueConstruct(this, 'Queue', {
      visibilityTimeout: Duration.seconds(4500),
      messageRetention: Duration.days(1),
      maxReceiveCount: 5
    });

    // Database - Phase 3 (conditionally created based on database.mode)
    let database: DatabaseConstruct | undefined;
    if (config.database.mode !== 'none') {
      if (!config.database.instanceType || !config.database.allocatedStorage ||
          config.database.backupRetention === undefined || config.database.multiAz === undefined) {
        throw new Error('Database configuration (instanceType, allocatedStorage, backupRetention, multiAz) is required when database.mode is not "none"');
      }

      // For private database, we need VPC
      const dbVpc = config.database.mode === 'private' ? vpc?.vpc : undefined;
      const publiclyAccessible = config.database.mode === 'public';

      database = new DatabaseConstruct(this, 'Database', {
        vpc: dbVpc,
        instanceType: config.database.instanceType,
        allocatedStorage: config.database.allocatedStorage,
        backupRetention: config.database.backupRetention,
        multiAz: config.database.multiAz,
        databaseName: 'FFMSampleLambdaDB',
        publiclyAccessible: publiclyAccessible
      });
    }

    // Lambda - Phase 4
    const lambdaFunc = new LambdaConstruct(this, 'Lambda', {
      vpc: vpc?.vpc,
      database: database?.instance,
      queue: queue.queue,
      dataBucket: storage.dataBucket,
      dbSecret: database?.secret,
      memorySize: config.lambda.memorySize,
      timeout: config.lambda.timeout,
      reservedConcurrentExecutions: config.lambda.reservedConcurrentExecutions
    });

    // Allow Lambda to connect to database (only if both exist and Lambda is in VPC)
    if (database && lambdaFunc.securityGroup && database.securityGroup) {
      database.securityGroup.addIngressRule(
        lambdaFunc.securityGroup,
        ec2.Port.tcp(5432),
        'Allow Lambda to connect to database'
      );
    }

    // API Gateway - Phase 5 (PUBLIC endpoint)
    const apiGateway = new ApiGatewayConstruct(this, 'ApiGateway', {
      lambdaFunction: lambdaFunc.function
    });

    // Monitoring - Phase 5
    const monitoring = new MonitoringConstruct(this, 'Monitoring', {
      lambdaFunction: lambdaFunc.function,
      scheduleExpression: config.monitoring.scheduleExpression,
      appName: 'Alpha',
      releaseLookbackHours: config.monitoring.releaseLookbackHours
    });

    // Add tags
    Tags.of(this).add('Environment', config.environment);
    Tags.of(this).add('Application', 'swift-lambda-sample');

    // Outputs - VPC (only if created)
    if (vpc) {
      new CfnOutput(this, 'VpcId', {
        value: vpc.vpc.vpcId,
        description: 'VPC ID'
      });
      new CfnOutput(this, 'VpcCidr', {
        value: vpc.vpc.vpcCidrBlock,
        description: 'VPC CIDR Block'
      });
    }
    new CfnOutput(this, 'BucketName', {
      value: storage.dataBucket.bucketName,
      description: 'S3 Data Bucket Name'
    });
    new CfnOutput(this, 'BucketArn', {
      value: storage.dataBucket.bucketArn,
      description: 'S3 Data Bucket ARN'
    });
    new CfnOutput(this, 'QueueUrl', {
      value: queue.queue.queueUrl,
      description: 'Main SQS Queue URL'
    });
    new CfnOutput(this, 'QueueArn', {
      value: queue.queue.queueArn,
      description: 'Main SQS Queue ARN'
    });
    new CfnOutput(this, 'DLQUrl', {
      value: queue.deadLetterQueue.queueUrl,
      description: 'Dead Letter Queue URL'
    });
    new CfnOutput(this, 'DLQArn', {
      value: queue.deadLetterQueue.queueArn,
      description: 'Dead Letter Queue ARN'
    });

    // Outputs - Database (only if created)
    if (database) {
      new CfnOutput(this, 'DatabaseEndpoint', {
        value: database.instance.dbInstanceEndpointAddress,
        description: 'RDS Database Endpoint'
      });
      new CfnOutput(this, 'DatabasePort', {
        value: database.instance.dbInstanceEndpointPort,
        description: 'RDS Database Port'
      });
      new CfnOutput(this, 'DatabaseName', {
        value: database.instance.instanceIdentifier,
        description: 'RDS Database Name'
      });
      new CfnOutput(this, 'DatabaseSecretArn', {
        value: database.secret.secretArn,
        description: 'RDS Database Secret ARN (contains credentials)'
      });
    }
    new CfnOutput(this, 'LambdaFunctionArn', {
      value: lambdaFunc.function.functionArn,
      description: 'Lambda Function ARN'
    });
    new CfnOutput(this, 'LambdaFunctionName', {
      value: lambdaFunc.function.functionName,
      description: 'Lambda Function Name'
    });
    new CfnOutput(this, 'ApiGatewayUrl', {
      value: apiGateway.api.url,
      description: 'API Gateway URL'
    });
    new CfnOutput(this, 'ApiGatewayId', {
      value: apiGateway.api.restApiId,
      description: 'API Gateway ID'
    });
    new CfnOutput(this, 'EventRuleName', {
      value: monitoring.eventRule.ruleName,
      description: 'CloudWatch Event Rule Name'
    });
  }

  /**
   * Validates the configuration to ensure valid combinations
   */
  private validateConfig(config: SwiftLambdaConfig): void {
    // Rule: Private database requires private Lambda mode (needs VPC)
    if (config.database.mode === 'private' && config.networking.lambdaMode !== 'private') {
      throw new Error(
        'Invalid configuration: database.mode "private" requires networking.lambdaMode "private" (database in VPC needs Lambda in VPC)'
      );
    }

    // Rule: Private Lambda mode requires VPC configuration
    if (config.networking.lambdaMode === 'private' && !config.networking.vpc) {
      throw new Error(
        'Invalid configuration: networking.lambdaMode "private" requires vpc configuration'
      );
    }

    // Warning: Public database is accessible from internet
    if (config.database.mode === 'public') {
      console.warn(
        '\n⚠️  WARNING: Database is configured as publicly accessible (database.mode: "public").\n' +
        '   This means the database will be accessible from the internet.\n' +
        '   Ensure proper security groups and strong credentials are in place.\n' +
        '   For production, consider using database.mode: "private".\n'
      );
    }

    // Info: Cost optimization message
    if (config.networking.lambdaMode === 'public' && config.database.mode === 'none') {
      // Use process.stderr to avoid interfering with CDK synth output
      process.stderr.write(
        '\n💰 MINIMAL COST MODE:\n' +
        '   - No VPC (Lambda in AWS-managed VPC)\n' +
        '   - No NAT Gateway\n' +
        '   - No Database\n' +
        '   - Cost: ~$0/month (only pay for Lambda invocations, S3, SQS usage)\n\n'
      );
    }
  }
}
