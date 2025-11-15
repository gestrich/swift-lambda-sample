import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { RemovalPolicy } from 'aws-cdk-lib';

export class StorageConstruct extends Construct {
  public readonly dataBucket: s3.Bucket;

  constructor(scope: Construct, id: string) {
    super(scope, id);

    this.dataBucket = new s3.Bucket(this, 'DataBucket', {
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,  // Delete bucket on stack deletion
      autoDeleteObjects: true  // Automatically delete all objects before deleting bucket
    });
  }
}
