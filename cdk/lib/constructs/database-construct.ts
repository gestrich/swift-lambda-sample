import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { RemovalPolicy, Duration } from 'aws-cdk-lib';

export interface DatabaseConstructProps {
  vpc: ec2.IVpc;
  instanceType: string;
  allocatedStorage: number;
  backupRetention: number;
  multiAz: boolean;
  databaseName: string;
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

    // RDS instance
    this.instance = new rds.DatabaseInstance(this, 'Instance', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_16
      }),
      instanceType: new ec2.InstanceType(props.instanceType),
      vpc: props.vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      securityGroups: [this.securityGroup],
      databaseName: props.databaseName,
      credentials: rds.Credentials.fromSecret(this.secret),
      allocatedStorage: props.allocatedStorage,
      backupRetention: Duration.days(props.backupRetention),
      multiAz: props.multiAz,
      removalPolicy: RemovalPolicy.DESTROY,  // Use RETAIN for prod
      deletionProtection: false  // Set to true for prod
    });
  }
}
