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
            name: "feature-lambda",
            targets: ["feature-lambda"]
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
            name: "sdk-cli-macros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "sdk-cli",
            dependencies: [
                .target(name: "sdk-cli-macros"),
            ],
            exclude: ["README.md"]
        ),
        .target(
            name: "sdk-aws",
            dependencies: [
                .target(name: "sdk-cli"),
            ]
        ),
        .target(
            name: "service-storage"
        ),
        .executableTarget(
            name: "feature-cli",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "service-deploy"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .target(
            name: "service-deploy",
            dependencies: [
                .target(name: "sdk-client"),
                .target(name: "service-storage"),
                .target(name: "sdk-cli"),
            ]
        ),
        .executableTarget(
            name: "feature-lambda",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoSecretsManager", package: "soto"),
                .product(name: "SotoDynamoDB", package: "soto"),
                .target(name: "sdk-client")
            ]
        ),
        .executableTarget(
            name: "feature-mac",
            dependencies: [
                .target(name: "sdk-client"),
                .target(name: "service-deploy"),
                .target(name: "service-storage"),
                .target(name: "sdk-cli"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .target(
            name: "sdk-client",
            dependencies: []
        ),
        .testTarget(
            name: "service-deploy-tests",
            dependencies: [
                .target(name: "service-deploy")
            ]
        ),
        .testTarget(
            name: "sdk-cli-tests",
            dependencies: [
                .target(name: "sdk-cli"),
                .target(name: "sdk-cli-macros"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        )
    ]
)
