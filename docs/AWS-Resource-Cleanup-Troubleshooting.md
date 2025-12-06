# AWS Resource Cleanup Troubleshooting

This document explains how to identify and clean up orphaned AWS resources that may block CDK deployments.

## Background

When CDK deployments fail partway through, or when infrastructure is manually deleted without using `cdk destroy`, orphaned resources can remain in AWS. These resources cause subsequent deployments to fail with errors like:

- `AWS::EarlyValidation::ResourceExistenceCheck` - CloudFormation's early validation detects name conflicts
- `Resource of type 'X' with identifier 'Y' already exists`
- `AlreadyExists` errors during resource creation

AWS introduced Early Validation (November 2025) which proactively checks for resource name conflicts before deployment starts, making these issues more visible.

## Finding Orphaned Resources

Run these commands to scan for resources with the `swift-lambda-sample` prefix. Replace `$AWS_PROFILE` with your configured profile name.

### Lambda Functions

```bash
aws lambda list-functions --profile $AWS_PROFILE \
  --query "Functions[?contains(FunctionName, 'swift-lambda-sample')].FunctionName" \
  --output table
```

### SQS Queues

```bash
aws sqs list-queues --queue-name-prefix swift-lambda-sample \
  --profile $AWS_PROFILE
```

### S3 Buckets

```bash
aws s3api list-buckets --profile $AWS_PROFILE \
  --query "Buckets[?contains(Name, 'swift-lambda-sample')].Name" \
  --output table
```

### RDS Instances

```bash
aws rds describe-db-instances --profile $AWS_PROFILE \
  --query "DBInstances[?contains(DBInstanceIdentifier, 'swift-lambda-sample')].{ID: DBInstanceIdentifier, Status: DBInstanceStatus}" \
  --output table
```

### CloudWatch Log Groups

```bash
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/lambda/swift-lambda-sample" \
  --profile $AWS_PROFILE \
  --query "logGroups[].logGroupName" \
  --output table
```

### Lambda Event Source Mappings

```bash
aws lambda list-event-source-mappings --profile $AWS_PROFILE \
  --query "EventSourceMappings[?contains(FunctionArn, 'swift-lambda-sample') || contains(EventSourceArn, 'swift-lambda-sample')].{UUID: UUID, Function: FunctionArn, Source: EventSourceArn, State: State}" \
  --output table
```

### API Gateway REST APIs

```bash
aws apigateway get-rest-apis --profile $AWS_PROFILE \
  --query "items[?contains(name, 'swift-lambda-sample') || contains(name, 'SwiftLambda')].{Name: name, ID: id}" \
  --output table
```

### IAM Roles

```bash
aws iam list-roles --profile $AWS_PROFILE \
  --query "Roles[?contains(RoleName, 'SwiftLambda') || contains(RoleName, 'swift-lambda')].RoleName" \
  --output table
```

### Secrets Manager Secrets

```bash
aws secretsmanager list-secrets --profile $AWS_PROFILE \
  --query "SecretList[?contains(Name, 'swift-lambda-sample') || contains(Name, 'SwiftLambda')].Name" \
  --output table
```

### CloudWatch Events Rules

```bash
aws events list-rules --profile $AWS_PROFILE \
  --query "Rules[?contains(Name, 'swift-lambda-sample') || contains(Name, 'SwiftLambda')].Name" \
  --output table
```

### EC2 Security Groups

```bash
aws ec2 describe-security-groups --profile $AWS_PROFILE \
  --filters "Name=group-name,Values=*swift-lambda*" \
  --query "SecurityGroups[].{Name: GroupName, ID: GroupId, VpcId: VpcId}" \
  --output table
```

### RDS DB Subnet Groups

```bash
aws rds describe-db-subnet-groups --profile $AWS_PROFILE \
  --query "DBSubnetGroups[?contains(DBSubnetGroupName, 'swift-lambda-sample')].DBSubnetGroupName" \
  --output table
```

### CloudFormation Stacks

```bash
aws cloudformation list-stacks --profile $AWS_PROFILE \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE CREATE_FAILED DELETE_FAILED UPDATE_ROLLBACK_COMPLETE \
  --query "StackSummaries[?contains(StackName, 'SwiftLambda') || contains(StackName, 'swift-lambda')].{Name: StackName, Status: StackStatus}" \
  --output table
```

## Deleting Orphaned Resources

Once you've identified orphaned resources, delete them in the correct order (dependencies first).

### 1. Lambda Event Source Mappings

```bash
aws lambda delete-event-source-mapping --uuid <UUID> --profile $AWS_PROFILE
```

### 2. Lambda Functions

```bash
aws lambda delete-function --function-name swift-lambda-sample --profile $AWS_PROFILE
```

### 3. CloudWatch Log Groups

```bash
aws logs delete-log-group --log-group-name "/aws/lambda/swift-lambda-sample" --profile $AWS_PROFILE
```

### 4. SQS Queues

```bash
aws sqs delete-queue --queue-url "https://sqs.<region>.amazonaws.com/<account-id>/swift-lambda-sample" --profile $AWS_PROFILE
aws sqs delete-queue --queue-url "https://sqs.<region>.amazonaws.com/<account-id>/swift-lambda-sample-dlq" --profile $AWS_PROFILE
```

Note: SQS queues have a 60-second delay before the name can be reused.

### 5. API Gateway REST APIs

```bash
aws apigateway delete-rest-api --rest-api-id <api-id> --profile $AWS_PROFILE
```

### 6. CloudWatch Events Rules

First remove all targets, then delete the rule:

```bash
# List targets
aws events list-targets-by-rule --rule <rule-name> --profile $AWS_PROFILE

# Remove targets
aws events remove-targets --rule <rule-name> --ids <target-id> --profile $AWS_PROFILE

# Delete rule
aws events delete-rule --name <rule-name> --profile $AWS_PROFILE
```

### 7. S3 Buckets

Empty the bucket first, then delete:

```bash
aws s3 rm s3://<bucket-name> --recursive --profile $AWS_PROFILE
aws s3 rb s3://<bucket-name> --profile $AWS_PROFILE
```

### 8. RDS Instances

```bash
# For dev environments (skip final snapshot)
aws rds delete-db-instance \
  --db-instance-identifier swift-lambda-sample \
  --skip-final-snapshot \
  --profile $AWS_PROFILE

# Wait for deletion (can take several minutes)
aws rds wait db-instance-deleted \
  --db-instance-identifier swift-lambda-sample \
  --profile $AWS_PROFILE
```

### 9. RDS DB Subnet Groups

Can only be deleted after the RDS instance is fully deleted:

```bash
aws rds delete-db-subnet-group \
  --db-subnet-group-name swift-lambda-sample \
  --profile $AWS_PROFILE
```

### 10. EC2 Security Groups

Security groups can only be deleted if not referenced by other resources:

```bash
aws ec2 delete-security-group --group-id <sg-id> --profile $AWS_PROFILE
```

### 11. Secrets Manager Secrets

```bash
# Force delete immediately (no recovery period)
aws secretsmanager delete-secret \
  --secret-id <secret-name> \
  --force-delete-without-recovery \
  --profile $AWS_PROFILE
```

### 12. IAM Roles

First delete attached policies, then the role:

```bash
# List attached policies
aws iam list-attached-role-policies --role-name <role-name> --profile $AWS_PROFILE

# Detach policies
aws iam detach-role-policy --role-name <role-name> --policy-arn <policy-arn> --profile $AWS_PROFILE

# List inline policies
aws iam list-role-policies --role-name <role-name> --profile $AWS_PROFILE

# Delete inline policies
aws iam delete-role-policy --role-name <role-name> --policy-name <policy-name> --profile $AWS_PROFILE

# Delete the role
aws iam delete-role --role-name <role-name> --profile $AWS_PROFILE
```

### 13. CloudFormation Stacks (if in failed state)

```bash
aws cloudformation delete-stack --stack-name SwiftLambdaSampleStack --profile $AWS_PROFILE

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name SwiftLambdaSampleStack --profile $AWS_PROFILE
```

## Common Issues

### Stack in ROLLBACK_COMPLETE State

Delete the stack before retrying deployment:

```bash
aws cloudformation delete-stack --stack-name SwiftLambdaSampleStack --profile $AWS_PROFILE
```

### Resource Still Shows After Deletion

Some resources (like SQS queues) have propagation delays. Wait 60 seconds and retry.

### Cannot Delete Security Group

Security groups may be referenced by other resources. Check for:
- Lambda functions using the VPC
- RDS instances
- VPC endpoints

Delete the referencing resources first.

### Cannot Delete DB Subnet Group

The RDS instance must be fully deleted first. Use `aws rds wait db-instance-deleted` to ensure completion.
