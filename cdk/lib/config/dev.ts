import { SwiftLambdaConfig } from './types';

// MINIMAL COST CONFIGURATION
// - No VPC (Lambda runs in AWS-managed VPC)
// - No NAT Gateway
// - No Database
// Cost: ~$0/month (only pay for Lambda invocations, S3, SQS usage)
export const devConfig: SwiftLambdaConfig = {
  environment: 'dev',

  networking: {
    lambdaMode: 'public'  // No VPC created, no NAT gateway costs
  },

  lambda: {
    memorySize: 10240,
    timeout: 900
  },

  database: {
    mode: 'none'  // No database created
  },

  monitoring: {
    scheduleExpression: 'cron(0 6 * * ? *)',
    releaseLookbackHours: 2160
  }
};

// ALTERNATIVE CONFIGURATIONS (uncomment to use):

// Public database configuration (no VPC, database is publicly accessible)
// Cost: ~$15-30/month
/*
export const devConfigPublicDb: SwiftLambdaConfig = {
  environment: 'dev',

  networking: {
    lambdaMode: 'public'
  },

  lambda: {
    memorySize: 10240,
    timeout: 900
  },

  database: {
    mode: 'public',
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
*/

// Private VPC and database configuration (full isolation)
// Cost: ~$47-62/month (NAT gateway + RDS)
/*
export const devConfigPrivate: SwiftLambdaConfig = {
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
*/
