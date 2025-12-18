// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "SwiftLambda",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "LambdaApp",
            targets: ["LambdaApp"]
        ),
        .executable(
            name: "CLIApp",
            targets: ["CLIApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/soto-project/soto.git", from: "7.10.0"),
        .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime.git", "2.0.0"..<"3.0.0"),
        .package(url: "https://github.com/swift-server/swift-aws-lambda-events.git", from: "0.5.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", "2.2.0"..<"3.0.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", "4.0.0"..<"5.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        // MARK: - Uniflow
        .target(
            name: "Uniflow",
            path: "Sources/sdks/Uniflow"
        ),
        // MARK: - CLI Macros
        .macro(
            name: "CLIMacrosSDK",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "Sources/sdks/CLIMacrosSDK"
        ),
        .target(
            name: "CLISDK",
            dependencies: [
                .target(name: "CLIMacrosSDK"),
            ],
            path: "Sources/sdks/CLISDK",
            exclude: ["README.md"]
        ),
        .target(
            name: "AWSSDK",
            dependencies: [
                .target(name: "CLISDK"),
                .target(name: "NodeCLISDK"),
            ],
            path: "Sources/sdks/AWSSDK"
        ),
        .target(
            name: "GitHubSDK",
            dependencies: [
                .target(name: "CLISDK"),
            ],
            path: "Sources/sdks/GitHubSDK"
        ),
        .target(
            name: "DockerCLISDK",
            dependencies: [
                .target(name: "CLISDK"),
            ],
            path: "Sources/sdks/DockerCLISDK"
        ),
        .target(
            name: "MinioSDK",
            dependencies: [
                .target(name: "DockerCLISDK"),
            ],
            path: "Sources/sdks/MinioSDK"
        ),
        .target(
            name: "PostgreSQLSDK",
            dependencies: [
                .target(name: "DockerCLISDK"),
            ],
            path: "Sources/sdks/PostgreSQLSDK"
        ),
        .target(
            name: "DynamoDBSDK",
            dependencies: [
                .target(name: "DockerCLISDK"),
            ],
            path: "Sources/sdks/DynamoDBSDK"
        ),
        .target(
            name: "BrewCLISDK",
            dependencies: [
                .target(name: "CLISDK"),
            ],
            path: "Sources/sdks/BrewCLISDK"
        ),
        .target(
            name: "NodeCLISDK",
            dependencies: [
                .target(name: "CLISDK"),
            ],
            path: "Sources/sdks/NodeCLISDK"
        ),
        .target(
            name: "StorageService",
            path: "Sources/services/StorageService"
        ),
        .target(
            name: "SetupFeature",
            dependencies: [
                .target(name: "Uniflow"),
                .target(name: "CLISDK"),
                .target(name: "BrewCLISDK"),
                .target(name: "NodeCLISDK"),
                .target(name: "DockerCLISDK"),
                .target(name: "AWSSDK"),
                .target(name: "GitHubSDK"),
            ],
            path: "Sources/features/SetupFeature"
        ),
        .target(
            name: "DeployCoreService",
            dependencies: [
                .target(name: "CLISDK"),
                .target(name: "ClientService"),
            ],
            path: "Sources/services/DeployCoreService"
        ),
        .target(
            name: "DeployLocalService",
            dependencies: [
                .target(name: "CLISDK"),
                .target(name: "DockerCLISDK"),
                .target(name: "MinioSDK"),
                .target(name: "PostgreSQLSDK"),
                .target(name: "DynamoDBSDK"),
                .target(name: "ClientService"),
                .target(name: "StorageService"),
                .target(name: "LambdaBuildService"),
                .target(name: "DeployCoreService"),
            ],
            path: "Sources/services/DeployLocalService"
        ),
        .target(
            name: "LambdaBuildService",
            dependencies: [
                .target(name: "CLISDK"),
            ],
            path: "Sources/services/LambdaBuildService"
        ),
        .target(
            name: "DeployRemoteFeature",
            dependencies: [
                .target(name: "Uniflow"),
                .target(name: "CLISDK"),
                .target(name: "DockerCLISDK"),
                .target(name: "AWSSDK"),
                .target(name: "GitHubSDK"),
                .target(name: "ClientService"),
                .target(name: "StorageService"),
                .target(name: "LambdaBuildService"),
                .target(name: "DeployCoreService"),
            ],
            path: "Sources/features/DeployRemoteFeature"
        ),
        .target(
            name: "DeployLocalXcodeFeature",
            dependencies: [
                .target(name: "Uniflow"),
                .target(name: "DeployLocalService"),
                .target(name: "CLISDK"),
                .target(name: "DeployCoreService"),
                .target(name: "LambdaBuildService"),
                .target(name: "ClientService"),
            ],
            path: "Sources/features/DeployLocalXcodeFeature"
        ),
        .target(
            name: "DeployLocalLinuxFeature",
            dependencies: [
                .target(name: "Uniflow"),
                .target(name: "DeployLocalService"),
                .target(name: "CLISDK"),
            ],
            path: "Sources/features/DeployLocalLinuxFeature"
        ),
        .executableTarget(
            name: "CLIApp",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "DeployRemoteFeature"),
                .target(name: "DeployLocalXcodeFeature"),
                .target(name: "DeployLocalLinuxFeature"),
                .target(name: "DeployLocalService"),
                .target(name: "DeployCoreService"),
                .target(name: "AWSSDK"),
                .target(name: "CLISDK"),
                .target(name: "GitHubSDK"),
            ],
            path: "Sources/apps/CLIApp",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .executableTarget(
            name: "LambdaApp",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoSecretsManager", package: "soto"),
                .product(name: "SotoDynamoDB", package: "soto"),
                .target(name: "ClientService")
            ],
            path: "Sources/apps/LambdaApp"
        ),
        .executableTarget(
            name: "MacApp",
            dependencies: [
                .target(name: "ClientService"),
                .target(name: "DeployRemoteFeature"),
                .target(name: "DeployLocalXcodeFeature"),
                .target(name: "DeployLocalLinuxFeature"),
                .target(name: "SetupFeature"),
                .target(name: "DeployLocalService"),
                .target(name: "DeployCoreService"),
                .target(name: "LambdaBuildService"),
                .target(name: "StorageService"),
                .target(name: "CLISDK"),
                .target(name: "BrewCLISDK"),
                .target(name: "NodeCLISDK"),
                .target(name: "DockerCLISDK"),
                .target(name: "AWSSDK"),
                .target(name: "GitHubSDK"),
            ],
            path: "Sources/apps/MacApp",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .target(
            name: "ClientService",
            path: "Sources/services/ClientService"
        ),
        .testTarget(
            name: "DeployRemoteFeatureTests",
            dependencies: [
                .target(name: "DeployRemoteFeature"),
                .target(name: "DeployLocalService"),
                .target(name: "DeployLocalLinuxFeature"),
                .target(name: "LambdaBuildService"),
                .target(name: "GitHubSDK"),
                .target(name: "DockerCLISDK"),
                .target(name: "NodeCLISDK"),
            ],
            path: "Tests/DeployRemoteFeatureTests"
        ),
        .testTarget(
            name: "CLISDKTests",
            dependencies: [
                .target(name: "CLISDK"),
                .target(name: "CLIMacrosSDK"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            path: "Tests/CLISDKTests"
        )
    ]
)
