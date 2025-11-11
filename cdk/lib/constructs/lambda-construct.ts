import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';
import { SqsEventSource } from 'aws-cdk-lib/aws-lambda-event-sources';
import * as path from 'path';

export interface LambdaConstructProps {
  vpc: ec2.IVpc;
  database: rds.DatabaseInstance;
  queue: sqs.Queue;
  dataBucket: s3.Bucket;
  dbSecret: secretsmanager.ISecret;
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

    // CloudWatch Logs group with automatic cleanup
    const logGroup = new logs.LogGroup(this, 'LogGroup', {
      logGroupName: '/aws/lambda/swift-lambda-sample',
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: RemovalPolicy.DESTROY
    });

    // Lambda function
    this.function = new lambda.Function(this, 'Function', {
      functionName: 'swift-lambda-sample',
      runtime: lambda.Runtime.PROVIDED_AL2,
      handler: 'lambda_function.main',
      code: lambda.Code.fromAsset(path.join(__dirname, '../../..', 'lambda_function_payload.zip')),
      vpc: props.vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      securityGroups: [this.securityGroup],
      memorySize: props.memorySize,
      timeout: Duration.seconds(props.timeout),
      reservedConcurrentExecutions: props.reservedConcurrentExecutions,
      logGroup: logGroup,
      environment: {
        POSTGRES_HOST: props.database.dbInstanceEndpointAddress,
        POSTGRES_PORT: props.database.dbInstanceEndpointPort,
        POSTGRES_USER_NAME: 'docker',
        POSTGRES_DBNAME: 'FFMSampleLambdaDB',
        POSTGRES_PASSWORD_SECRET_ID: props.dbSecret.secretName,
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
