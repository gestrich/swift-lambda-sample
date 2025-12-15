import Foundation

/// Parsed stack output values
public struct CDKStackOutputs: Equatable, Sendable {
    public let apiGatewayUrl: String?
    public let lambdaFunctionName: String?
    public let bucketName: String?
    public let allOutputs: [String: String]

    public init(
        apiGatewayUrl: String? = nil,
        lambdaFunctionName: String? = nil,
        bucketName: String? = nil,
        allOutputs: [String: String] = [:]
    ) {
        self.apiGatewayUrl = apiGatewayUrl
        self.lambdaFunctionName = lambdaFunctionName
        self.bucketName = bucketName
        self.allOutputs = allOutputs
    }

    public static func from(_ outputs: [String: String]) -> CDKStackOutputs {
        CDKStackOutputs(
            apiGatewayUrl: outputs["ApiGatewayUrl"],
            lambdaFunctionName: outputs["LambdaFunctionName"],
            bucketName: outputs["BucketName"],
            allOutputs: outputs
        )
    }
}
