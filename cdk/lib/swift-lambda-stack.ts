import { Stack, StackProps, Tags, CfnOutput } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { SwiftLambdaConfig } from './config/types';
import { VpcConstruct } from './constructs/vpc-construct';

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
  }
}
