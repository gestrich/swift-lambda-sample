export interface SwiftLambdaConfig {
  environment: 'dev' | 'staging' | 'prod';
  vpc: {
    cidr: string;
    maxAzs: number;
    natGateways: number;
  };
  lambda: {
    memorySize: number;
    timeout: number;
    reservedConcurrentExecutions?: number;
  };
  database: {
    instanceType: string;
    allocatedStorage: number;
    backupRetention: number;
    multiAz: boolean;
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
