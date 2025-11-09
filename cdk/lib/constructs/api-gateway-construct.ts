import { Construct } from 'constructs';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';

export interface ApiGatewayConstructProps {
  vpc: ec2.IVpc;
  lambdaFunction: lambda.IFunction;
  allowedCidrs?: string[];
}

export class ApiGatewayConstruct extends Construct {
  public readonly api: apigateway.RestApi;
  public readonly vpcEndpoint: ec2.InterfaceVpcEndpoint;

  constructor(scope: Construct, id: string, props: ApiGatewayConstructProps) {
    super(scope, id);

    // Security group for VPC endpoint
    const endpointSecurityGroup = new ec2.SecurityGroup(this, 'EndpointSg', {
      vpc: props.vpc,
      description: 'API Gateway VPC Endpoint Security Group',
      allowAllOutbound: true
    });

    // Add ingress rules for allowed CIDRs
    const allowedCidrs = props.allowedCidrs || ['10.0.0.0/8'];
    allowedCidrs.forEach((cidr, index) => {
      endpointSecurityGroup.addIngressRule(
        ec2.Peer.ipv4(cidr),
        ec2.Port.tcp(443),
        `Allow HTTPS from ${cidr}`
      );
    });

    // VPC Endpoint for API Gateway
    this.vpcEndpoint = new ec2.InterfaceVpcEndpoint(this, 'VpcEndpoint', {
      vpc: props.vpc,
      service: ec2.InterfaceVpcEndpointAwsService.APIGATEWAY,
      privateDnsEnabled: false,
      securityGroups: [endpointSecurityGroup],
      subnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS }
    });

    // Create REST API with Lambda integration
    this.api = new apigateway.RestApi(this, 'Api', {
      restApiName: 'Swift Lambda Sample API',
      description: 'Swift Lambda Sample API',
      endpointConfiguration: {
        types: [apigateway.EndpointType.PRIVATE],
        vpcEndpoints: [this.vpcEndpoint]
      },
      policy: new iam.PolicyDocument({
        statements: [
          // Allow from VPC endpoint
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.AnyPrincipal()],
            actions: ['execute-api:Invoke'],
            resources: ['execute-api:/*'],
            conditions: {
              StringEquals: {
                'aws:SourceVpce': this.vpcEndpoint.vpcEndpointId
              }
            }
          }),
          // Deny if not from VPC endpoint
          new iam.PolicyStatement({
            effect: iam.Effect.DENY,
            principals: [new iam.AnyPrincipal()],
            actions: ['execute-api:Invoke'],
            resources: ['execute-api:/*'],
            conditions: {
              StringNotEquals: {
                'aws:SourceVpce': this.vpcEndpoint.vpcEndpointId
              }
            }
          })
        ]
      }),
      deployOptions: {
        stageName: 'prod',
        metricsEnabled: true,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true
      }
    });

    // Add Lambda integration
    const lambdaIntegration = new apigateway.LambdaIntegration(props.lambdaFunction, {
      proxy: true
    });

    // Create API resource and method
    const apiResource = this.api.root.addResource('api');
    apiResource.addMethod('ANY', lambdaIntegration);

    // Add proxy resource for catch-all
    const proxyResource = apiResource.addResource('{proxy+}');
    proxyResource.addMethod('ANY', lambdaIntegration);

    // Grant Lambda invoke permission to API Gateway
    props.lambdaFunction.grantInvoke(new iam.ServicePrincipal('apigateway.amazonaws.com'));
  }
}
