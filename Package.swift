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
            targets: ["app-lambda"]
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
            name: "d-sdk-cli-macros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "d-sdk-cli",
            dependencies: [
                .target(name: "d-sdk-cli-macros"),
            ],
            exclude: ["README.md"]
        ),
        .target(
            name: "d-sdk-aws",
            dependencies: [
                .target(name: "d-sdk-cli"),
                .target(name: "d-sdk-cli-node"),
            ]
        ),
        .target(
            name: "d-sdk-github",
            dependencies: [
                .target(name: "d-sdk-cli"),
            ]
        ),
        .target(
            name: "d-sdk-cli-docker",
            dependencies: [
                .target(name: "d-sdk-cli"),
            ]
        ),
        .target(
            name: "d-sdk-cli-brew",
            dependencies: [
                .target(name: "d-sdk-cli"),
            ]
        ),
        .target(
            name: "d-sdk-cli-node",
            dependencies: [
                .target(name: "d-sdk-cli"),
            ]
        ),
        .target(
            name: "service-storage"
        ),
        .target(
            name: "service-setup"
        ),
        .target(
            name: "service-deploy-core",
            dependencies: [
                .target(name: "d-sdk-cli"),
                .target(name: "d-sdk-client"),
            ]
        ),
        .target(
            name: "service-deploy-local",
            dependencies: [
                .target(name: "d-sdk-cli"),
                .target(name: "d-sdk-cli-docker"),
                .target(name: "d-sdk-client"),
                .target(name: "service-storage"),
                .target(name: "service-lambda-build"),
                .target(name: "service-deploy-core"),
            ]
        ),
        .target(
            name: "workflows-setup",
            dependencies: [
                .target(name: "d-sdk-cli"),
                .target(name: "d-sdk-cli-brew"),
                .target(name: "d-sdk-cli-node"),
                .target(name: "d-sdk-cli-docker"),
                .target(name: "d-sdk-aws"),
                .target(name: "d-sdk-github"),
                .target(name: "service-setup"),
            ]
        ),
        .target(
            name: "service-lambda-build",
            dependencies: [
                .target(name: "d-sdk-cli"),
            ]
        ),
        .target(
            name: "workflows-deploy-remote",
            dependencies: [
                .target(name: "d-sdk-cli"),
                .target(name: "d-sdk-aws"),
                .target(name: "d-sdk-github"),
                .target(name: "service-deploy-remote"),
                .target(name: "service-deploy-core"),
            ]
        ),
        .executableTarget(
            name: "app-cli",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "workflows-deploy-remote"),
                .target(name: "service-deploy-remote"),
                .target(name: "service-deploy-local"),
                .target(name: "service-deploy-core"),
                .target(name: "d-sdk-aws"),
                .target(name: "d-sdk-cli"),
                .target(name: "d-sdk-github"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .target(
            name: "service-deploy-remote",
            dependencies: [
                .target(name: "d-sdk-client"),
                .target(name: "service-storage"),
                .target(name: "service-lambda-build"),
                .target(name: "d-sdk-cli"),
                .target(name: "d-sdk-cli-docker"),
                .target(name: "d-sdk-aws"),
                .target(name: "d-sdk-github"),
                .target(name: "service-deploy-core"),
            ]
        ),
        .executableTarget(
            name: "app-lambda",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoSecretsManager", package: "soto"),
                .product(name: "SotoDynamoDB", package: "soto"),
                .target(name: "d-sdk-client")
            ]
        ),
        .executableTarget(
            name: "app-mac",
            dependencies: [
                .target(name: "d-sdk-client"),
                .target(name: "workflows-deploy-remote"),
                .target(name: "workflows-setup"),
                .target(name: "service-deploy-remote"),
                .target(name: "service-deploy-local"),
                .target(name: "service-deploy-core"),
                .target(name: "service-lambda-build"),
                .target(name: "service-storage"),
                .target(name: "service-setup"),
                .target(name: "d-sdk-cli"),
                .target(name: "d-sdk-cli-brew"),
                .target(name: "d-sdk-cli-node"),
                .target(name: "d-sdk-cli-docker"),
                .target(name: "d-sdk-aws"),
                .target(name: "d-sdk-github"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .target(
            name: "d-sdk-client",
            dependencies: []
        ),
        .testTarget(
            name: "service-deploy-remote-tests",
            dependencies: [
                .target(name: "service-deploy-remote"),
                .target(name: "d-sdk-github"),
            ]
        ),
        .testTarget(
            name: "sdk-cli-tests",
            dependencies: [
                .target(name: "d-sdk-cli"),
                .target(name: "d-sdk-cli-macros"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        )
    ]
)
