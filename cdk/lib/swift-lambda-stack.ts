import { Stack, StackProps, Tags, CfnOutput, Duration } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { SwiftLambdaConfig } from './config/types';
import { VpcConstruct } from './constructs/vpc-construct';
import { StorageConstruct } from './constructs/storage-construct';
import { QueueConstruct } from './constructs/queue-construct';

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
  }
}
