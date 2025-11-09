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
