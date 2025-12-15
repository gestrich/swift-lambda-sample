import sdk_aws
import Foundation

/// Progress snapshot during deployment/destroy operations.
/// This is a typealias to the generic DeploymentProgress from sdk-aws.
public typealias CDKDeploymentProgress = DeploymentProgress

/// Progress snapshot for a single resource.
/// This is a typealias to the generic ResourceProgress from sdk-aws.
public typealias ResourceProgressSnapshot = ResourceProgress

/// Status of a resource during deployment.
/// This is a typealias to the generic ResourceStatus from sdk-aws.
public typealias ResourceStatusSnapshot = ResourceStatus
