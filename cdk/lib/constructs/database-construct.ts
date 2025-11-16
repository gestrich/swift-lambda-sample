import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { RemovalPolicy, Duration } from 'aws-cdk-lib';

export interface DatabaseConstructProps {
  vpc: ec2.IVpc;  // Required - RDS always needs a VPC
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
  public readonly securityGroup: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props: DatabaseConstructProps) {
    super(scope, id);

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

    // Security group for database
    this.securityGroup = new ec2.SecurityGroup(this, 'SecurityGroup', {
      vpc: props.vpc,
      description: 'RDS PostgreSQL Security Group',
      allowAllOutbound: false
    });

    // For public databases, allow inbound connections from anywhere
    if (props.publiclyAccessible) {
      this.securityGroup.addIngressRule(
        ec2.Peer.anyIpv4(),
        ec2.Port.tcp(5432),
        'Allow PostgreSQL access from internet (public database)'
      );
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

    // Add VPC configuration (always required for RDS)
    instanceConfig.vpc = props.vpc;
    instanceConfig.vpcSubnets = {
      subnetType: props.publiclyAccessible
        ? ec2.SubnetType.PUBLIC
        : ec2.SubnetType.PRIVATE_WITH_EGRESS
    };
    instanceConfig.securityGroups = [this.securityGroup];

    // RDS instance
    this.instance = new rds.DatabaseInstance(this, 'Instance', instanceConfig);
  }
}
