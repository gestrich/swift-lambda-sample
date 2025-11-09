import { Construct } from 'constructs';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';

export interface ApiGatewayConstructProps {
  lambdaFunction: lambda.IFunction;
}

export class ApiGatewayConstruct extends Construct {
  public readonly api: apigateway.RestApi;

  constructor(scope: Construct, id: string, props: ApiGatewayConstructProps) {
    super(scope, id);

    // Create REST API with Lambda integration (PUBLIC endpoint - no resource policy for open access)
    this.api = new apigateway.RestApi(this, 'Api', {
      restApiName: 'Swift Lambda Sample API',
      description: 'Swift Lambda Sample API',
      endpointConfiguration: {
        types: [apigateway.EndpointType.REGIONAL]
      },
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
