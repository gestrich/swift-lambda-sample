import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { RemovalPolicy, Duration } from 'aws-cdk-lib';

export interface DatabaseConstructProps {
  vpc?: ec2.IVpc;  // Optional - only required for private databases
  instanceType: string;
  allocatedStorage: number;
  backupRetention: number;
  multiAz: boolean;
  databaseName: string;
  publiclyAccessible: boolean;  // true = public database, false = private in VPC
}

export class DatabaseConstruct extends Construct {
  public readonly instance: rds.DatabaseInstance;
  public readonly secret: secretsmanager.Secret;
  public readonly securityGroup?: ec2.SecurityGroup;  // Optional - only for private databases

  constructor(scope: Construct, id: string, props: DatabaseConstructProps) {
    super(scope, id);

    // Validate: private database requires VPC
    if (!props.publiclyAccessible && !props.vpc) {
      throw new Error('VPC is required for private database (publiclyAccessible: false)');
    }

    // Create secret for master password
    this.secret = new secretsmanager.Secret(this, 'DbPassword', {
      description: 'RDS database password',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'docker' }),
        generateStringKey: 'password',
        excludePunctuation: true,
        passwordLength: 32
      }
    });

    // Security group for database (only for private databases in VPC)
    if (props.vpc && !props.publiclyAccessible) {
      this.securityGroup = new ec2.SecurityGroup(this, 'SecurityGroup', {
        vpc: props.vpc,
        description: 'RDS PostgreSQL Security Group',
        allowAllOutbound: false
      });
    }

    // Build RDS instance configuration
    const instanceConfig: any = {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_16
      }),
      instanceType: new ec2.InstanceType(props.instanceType),
      databaseName: props.databaseName,
      credentials: rds.Credentials.fromSecret(this.secret),
      allocatedStorage: props.allocatedStorage,
      backupRetention: Duration.days(props.backupRetention),
      multiAz: props.multiAz,
      publiclyAccessible: props.publiclyAccessible,
      removalPolicy: RemovalPolicy.DESTROY,  // Use RETAIN for prod
      deletionProtection: false  // Set to true for prod
    };

    // Add VPC-specific configuration if VPC is provided
    if (props.vpc) {
      instanceConfig.vpc = props.vpc;
      instanceConfig.vpcSubnets = {
        subnetType: props.publiclyAccessible
          ? ec2.SubnetType.PUBLIC
          : ec2.SubnetType.PRIVATE_WITH_EGRESS
      };
      if (this.securityGroup) {
        instanceConfig.securityGroups = [this.securityGroup];
      }
    }

    // RDS instance
    this.instance = new rds.DatabaseInstance(this, 'Instance', instanceConfig);
  }
}
