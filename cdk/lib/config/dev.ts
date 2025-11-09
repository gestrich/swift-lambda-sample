import { SwiftLambdaConfig } from './types';

export const devConfig: SwiftLambdaConfig = {
  environment: 'dev',
  vpc: {
    cidr: '10.0.0.0/16',
    maxAzs: 2,
    natGateways: 1  // Single NAT Gateway for cost optimization
  },
  lambda: {
    memorySize: 10240,
    timeout: 900
  },
  database: {
    instanceType: 'db.t3.micro',
    allocatedStorage: 10,
    backupRetention: 1,
    multiAz: false  // Single AZ for dev
  },
  monitoring: {
    scheduleExpression: 'cron(0 6 * * ? *)',
    releaseLookbackHours: 2160
  }
};
