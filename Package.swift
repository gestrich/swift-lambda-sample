// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftLambda",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(
            name: "SwiftLambda",
            targets: ["SwiftLambda"]
        ),
        .executable(
            name: "MacApp",
            targets: ["MacApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/soto-project/soto.git", "6.8.0"..<"7.0.0"),
        .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime.git", "2.0.0"..<"3.0.0"),
        .package(url: "https://github.com/swift-server/swift-aws-lambda-events.git", from: "0.5.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", "2.2.0"..<"3.0.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", "4.0.0"..<"5.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "MacApp",
            dependencies: [],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .executableTarget(
            name: "SwiftDeploy",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "SwiftLambda",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
                .target(name: "SwiftServerApp")
            ]
        ),
        .target(
            name: "SwiftServerApp",
            dependencies: [
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoSecretsManager", package: "soto"),
            ]
        ),
        .testTarget(
            name: "SwiftDeployTests",
            dependencies: [
                .target(name: "SwiftDeploy")
            ]
        ),
        .testTarget(
            name: "SwiftServerAppTests",
            dependencies: [
                .target(name: "SwiftServerApp")
            ]
        )
    ]
)
