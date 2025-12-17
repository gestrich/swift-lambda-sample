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
            name: "app-lambda",
            targets: ["a-app-lambda"]
        ),
        .executable(
            name: "app-cli",
            targets: ["a-app-cli"]
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
            name: "c-service-setup"
        ),
        .target(
            name: "c-service-deploy-core",
            dependencies: [
                .target(name: "CLISDK"),
                .target(name: "ClientService"),
            ]
        ),
        .target(
            name: "c-service-deploy-local",
            dependencies: [
                .target(name: "CLISDK"),
                .target(name: "DockerCLISDK"),
                .target(name: "MinioSDK"),
                .target(name: "PostgreSQLSDK"),
                .target(name: "DynamoDBSDK"),
                .target(name: "ClientService"),
                .target(name: "StorageService"),
                .target(name: "c-service-lambda-build"),
                .target(name: "c-service-deploy-core"),
            ]
        ),
        .target(
            name: "b-workflow-setup",
            dependencies: [
                .target(name: "CLISDK"),
                .target(name: "BrewCLISDK"),
                .target(name: "NodeCLISDK"),
                .target(name: "DockerCLISDK"),
                .target(name: "AWSSDK"),
                .target(name: "GitHubSDK"),
                .target(name: "c-service-setup"),
            ]
        ),
        .target(
            name: "c-service-lambda-build",
            dependencies: [
                .target(name: "CLISDK"),
            ]
        ),
        .target(
            name: "b-workflow-deploy-remote",
            dependencies: [
                .target(name: "CLISDK"),
                .target(name: "AWSSDK"),
                .target(name: "GitHubSDK"),
                .target(name: "c-service-deploy-remote"),
                .target(name: "c-service-deploy-core"),
            ]
        ),
        .target(
            name: "b-workflow-deploy-local-xcode",
            dependencies: [
                .target(name: "c-service-deploy-local"),
                .target(name: "CLISDK"),
            ]
        ),
        .target(
            name: "b-workflow-deploy-local-linux",
            dependencies: [
                .target(name: "c-service-deploy-local"),
                .target(name: "CLISDK"),
            ]
        ),
        .executableTarget(
            name: "a-app-cli",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "b-workflow-deploy-remote"),
                .target(name: "b-workflow-deploy-local-xcode"),
                .target(name: "b-workflow-deploy-local-linux"),
                .target(name: "c-service-deploy-remote"),
                .target(name: "c-service-deploy-local"),
                .target(name: "c-service-deploy-core"),
                .target(name: "AWSSDK"),
                .target(name: "CLISDK"),
                .target(name: "GitHubSDK"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .target(
            name: "c-service-deploy-remote",
            dependencies: [
                .target(name: "ClientService"),
                .target(name: "StorageService"),
                .target(name: "c-service-lambda-build"),
                .target(name: "CLISDK"),
                .target(name: "DockerCLISDK"),
                .target(name: "AWSSDK"),
                .target(name: "GitHubSDK"),
                .target(name: "c-service-deploy-core"),
            ]
        ),
        .executableTarget(
            name: "a-app-lambda",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoSecretsManager", package: "soto"),
                .product(name: "SotoDynamoDB", package: "soto"),
                .target(name: "ClientService")
            ]
        ),
        .executableTarget(
            name: "a-app-mac",
            dependencies: [
                .target(name: "ClientService"),
                .target(name: "b-workflow-deploy-remote"),
                .target(name: "b-workflow-deploy-local-xcode"),
                .target(name: "b-workflow-deploy-local-linux"),
                .target(name: "b-workflow-setup"),
                .target(name: "c-service-deploy-remote"),
                .target(name: "c-service-deploy-local"),
                .target(name: "c-service-deploy-core"),
                .target(name: "c-service-lambda-build"),
                .target(name: "StorageService"),
                .target(name: "c-service-setup"),
                .target(name: "CLISDK"),
                .target(name: "BrewCLISDK"),
                .target(name: "NodeCLISDK"),
                .target(name: "DockerCLISDK"),
                .target(name: "AWSSDK"),
                .target(name: "GitHubSDK"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .target(
            name: "ClientService",
            path: "Sources/services/ClientService"
        ),
        .testTarget(
            name: "c-service-deploy-remote-tests",
            dependencies: [
                .target(name: "c-service-deploy-remote"),
                .target(name: "c-service-deploy-local"),
                .target(name: "c-service-lambda-build"),
                .target(name: "GitHubSDK"),
                .target(name: "DockerCLISDK"),
                .target(name: "NodeCLISDK"),
            ]
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
