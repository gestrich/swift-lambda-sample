#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { SwiftLambdaStack } from '../lib/swift-lambda-stack';
import { devConfig } from '../lib/config/dev';
import { SwiftLambdaConfig } from '../lib/config/types';

const app = new cdk.App();

// Read context parameters from command line
const skipPostgres = app.node.tryGetContext('skipPostgres') === 'true';
const skipNATGateway = app.node.tryGetContext('skipNATGateway') === 'true';

// Build configuration based on context parameters
let config: SwiftLambdaConfig;

if (!skipPostgres && !skipNATGateway) {
  // Full deployment: VPC + NAT Gateway + Private Database
  console.log('💰 FULL DEPLOYMENT MODE:');
  console.log('   - VPC with NAT Gateway');
  console.log('   - Private RDS PostgreSQL database');
  console.log('   - Cost: ~$47-62/month (NAT gateway ~$32/mo + RDS ~$15-30/mo)');
  console.log('');

  config = {
    environment: 'dev',
    networking: {
      lambdaMode: 'private',
      vpc: {
        cidr: '10.0.0.0/16',
        maxAzs: 2,
        natGateways: 1
      }
    },
    lambda: {
      memorySize: 10240,
      timeout: 900
    },
    database: {
      mode: 'private',
      instanceType: 't3.micro',
      allocatedStorage: 10,
      backupRetention: 1,
      multiAz: false
    },
    monitoring: {
      scheduleExpression: 'cron(0 6 * * ? *)',
      releaseLookbackHours: 2160
    }
  };
} else if (!skipPostgres && skipNATGateway) {
  // Public database mode: Lambda in AWS-managed VPC + public database
  // No VPC needed for Lambda, database is publicly accessible
  console.log('💰 PUBLIC DATABASE MODE (NO NAT):');
  console.log('   - Lambda in AWS-managed VPC (public)');
  console.log('   - Public RDS PostgreSQL database (internet accessible)');
  console.log('   - VPC created for database only (required by RDS)');
  console.log('   - Cost: ~$15-30/month (RDS only)');
  console.log('');
  console.log('⚠️  WARNING: Database will be publicly accessible.');
  console.log('   Ensure strong credentials and security groups are in place.');
  console.log('');

  config = {
    environment: 'dev',
    networking: {
      lambdaMode: 'public'  // Lambda NOT in VPC, uses AWS-managed VPC
    },
    lambda: {
      memorySize: 10240,
      timeout: 900
    },
    database: {
      mode: 'public',  // Database is publicly accessible
      instanceType: 't3.micro',
      allocatedStorage: 10,
      backupRetention: 1,
      multiAz: false
    },
    monitoring: {
      scheduleExpression: 'cron(0 6 * * ? *)',
      releaseLookbackHours: 2160
    }
  };
} else {
  // Minimal deployment: No VPC, No NAT Gateway, No Database (default)
  console.log('💰 MINIMAL COST MODE:');
  console.log('   - No VPC (Lambda in AWS-managed VPC)');
  console.log('   - No NAT Gateway');
  console.log('   - No Database');
  console.log('   - Cost: ~$0/month (only pay for Lambda invocations, S3, SQS usage)');
  console.log('');

  config = devConfig;
}

new SwiftLambdaStack(app, 'SwiftLambdaSampleStack', {
  config: config,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  description: 'Swift Lambda Sample infrastructure - Phase 3: VPC, S3, SQS, RDS'
});
