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

    // VPC - Phase 1
    const vpc = new VpcConstruct(this, 'Vpc', {
      cidr: config.vpc.cidr,
      maxAzs: config.vpc.maxAzs,
      natGateways: config.vpc.natGateways
    });

    // Storage - Phase 2
    const storage = new StorageConstruct(this, 'Storage');

    // Queue - Phase 2
    const queue = new QueueConstruct(this, 'Queue', {
      visibilityTimeout: Duration.seconds(4500),
      messageRetention: Duration.days(1),
      maxReceiveCount: 5
    });

    // Database - Phase 3
    const database = new DatabaseConstruct(this, 'Database', {
      vpc: vpc.vpc,
      instanceType: config.database.instanceType,
      allocatedStorage: config.database.allocatedStorage,
      backupRetention: config.database.backupRetention,
      multiAz: config.database.multiAz,
      databaseName: 'FFMSampleLambdaDB'
    });

    // Lambda - Phase 4
    const lambdaFunc = new LambdaConstruct(this, 'Lambda', {
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
      lambdaFunc.securityGroup,
      ec2.Port.tcp(5432),
      'Allow Lambda to connect to database'
    );

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

    // Outputs
    new CfnOutput(this, 'VpcId', {
      value: vpc.vpc.vpcId,
      description: 'VPC ID'
    });
    new CfnOutput(this, 'VpcCidr', {
      value: vpc.vpc.vpcCidrBlock,
      description: 'VPC CIDR Block'
    });
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
}
