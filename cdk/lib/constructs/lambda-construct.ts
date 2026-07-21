import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';
import { SqsEventSource } from 'aws-cdk-lib/aws-lambda-event-sources';
import * as path from 'path';

export interface LambdaConstructProps {
  vpc?: ec2.IVpc;  // Optional - only for private Lambda mode
  database?: rds.DatabaseInstance;  // Optional - only if database is enabled
  queue: sqs.Queue;
  dataBucket: s3.Bucket;
  dynamoDbTable: dynamodb.Table;
  dbSecret?: secretsmanager.ISecret;  // Optional - only if database is enabled
  memorySize: number;
  timeout: number;
  reservedConcurrentExecutions?: number;
}

export class LambdaConstruct extends Construct {
  public readonly function: lambda.Function;
  public readonly securityGroup?: ec2.SecurityGroup;  // Optional - only for VPC Lambda

  constructor(scope: Construct, id: string, props: LambdaConstructProps) {
    super(scope, id);

    // Security group for Lambda (only if VPC is provided)
    if (props.vpc) {
      this.securityGroup = new ec2.SecurityGroup(this, 'SecurityGroup', {
        vpc: props.vpc,
        description: 'Lambda VPC Security Group',
        allowAllOutbound: true
      });
    }

    // CloudWatch Logs group with automatic cleanup
    const logGroup = new logs.LogGroup(this, 'LogGroup', {
      logGroupName: '/aws/lambda/swift-lambda-sample',
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: RemovalPolicy.DESTROY
    });

    // Build environment variables
    const environment: { [key: string]: string } = {
      SQS_URL: props.queue.queueUrl,
      S3_BUCKET_NAME: props.dataBucket.bucketName,
      DYNAMODB_TABLE_NAME: props.dynamoDbTable.tableName
    };

    // Add database environment variables if database is enabled
    if (props.database && props.dbSecret) {
      environment.POSTGRES_HOST = props.database.dbInstanceEndpointAddress;
      environment.POSTGRES_PORT = props.database.dbInstanceEndpointPort;
      environment.POSTGRES_USER_NAME = 'docker';
      environment.POSTGRES_DBNAME = 'FFMSampleLambdaDB';
      environment.POSTGRES_PASSWORD_SECRET_ID = props.dbSecret.secretName;
    }

    // Build Lambda function configuration
    const functionConfig: any = {
      functionName: 'swift-lambda-sample',
      runtime: lambda.Runtime.PROVIDED_AL2023,
      handler: 'lambda_function.main',
      code: lambda.Code.fromAsset(path.join(__dirname, '../../..', 'lambda.zip')),
      memorySize: props.memorySize,
      timeout: Duration.seconds(props.timeout),
      reservedConcurrentExecutions: props.reservedConcurrentExecutions,
      logGroup: logGroup,
      environment: environment
    };

    // Add VPC configuration if VPC is provided
    if (props.vpc && this.securityGroup) {
      functionConfig.vpc = props.vpc;
      functionConfig.vpcSubnets = { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS };
      functionConfig.securityGroups = [this.securityGroup];
    }

    // Lambda function
    this.function = new lambda.Function(this, 'Function', functionConfig);

    // Grant permissions
    props.dataBucket.grantReadWrite(this.function);
    props.queue.grantConsumeMessages(this.function);
    props.queue.grantSendMessages(this.function);
    props.dynamoDbTable.grantReadWriteData(this.function);

    // Grant database secret read permission if database is enabled
    if (props.dbSecret) {
      props.dbSecret.grantRead(this.function);
    }

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
