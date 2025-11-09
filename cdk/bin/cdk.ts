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
  description: 'Swift Lambda Sample infrastructure - Phase 3: VPC, S3, SQS, RDS'
});
