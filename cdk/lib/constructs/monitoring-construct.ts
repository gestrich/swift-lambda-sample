import { Construct } from 'constructs';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as lambda from 'aws-cdk-lib/aws-lambda';

export interface MonitoringConstructProps {
  lambdaFunction: lambda.IFunction;
  scheduleExpression: string;
  appName: string;
  releaseLookbackHours: number;
}

export class MonitoringConstruct extends Construct {
  public readonly eventRule: events.Rule;

  constructor(scope: Construct, id: string, props: MonitoringConstructProps) {
    super(scope, id);

    // CloudWatch Events Rule for scheduled invocations
    this.eventRule = new events.Rule(this, 'ScheduleRule', {
      schedule: events.Schedule.expression(props.scheduleExpression),
      description: 'Stack Analytics Analysis trigger',
      enabled: true
    });

    // Add Lambda function as target
    // CloudWatch will send a standard scheduled event (no custom payload)
    this.eventRule.addTarget(
      new targets.LambdaFunction(props.lambdaFunction)
    );
  }
}
