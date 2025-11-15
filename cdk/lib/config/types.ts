export interface SwiftLambdaConfig {
  environment: 'dev' | 'staging' | 'prod';

  // Network configuration
  networking: {
    // 'public' = Lambda runs in AWS-managed VPC (no VPC created, no NAT costs)
    // 'private' = Lambda in custom VPC with NAT gateway (required for private database)
    lambdaMode: 'public' | 'private';
    // VPC settings (only used if lambdaMode is 'private')
    vpc?: {
      cidr: string;
      maxAzs: number;
      natGateways: number;
    };
  };

  lambda: {
    memorySize: number;
    timeout: number;
    reservedConcurrentExecutions?: number;
  };

  // Database configuration
  database: {
    // 'none' = No database created
    // 'public' = RDS with publiclyAccessible=true (internet-accessible, no VPC required)
    // 'private' = RDS in private subnet (requires lambdaMode: 'private')
    mode: 'none' | 'public' | 'private';
    // Database settings (only used if mode is not 'none')
    instanceType?: string;
    allocatedStorage?: number;
    backupRetention?: number;
    multiAz?: boolean;
  };

  monitoring: {
    scheduleExpression: string;
    releaseLookbackHours: number;
  };

  github?: {
    repository: string;
    oidcProviderArn: string;
  };
}
