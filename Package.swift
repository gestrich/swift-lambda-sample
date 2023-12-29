// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwiftLambda",
    platforms: [
        .macOS("13.0")
    ],
    products: [
        .executable(
            name: "SwiftLambda",
            targets: ["SwiftLambda"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/gestrich/swift-server-utilities.git", "0.1.4"..<"0.2.0"),
        .package(url: "https://github.com/soto-project/soto.git", "6.8.0"..<"7.0.0"),
        .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime.git", "0.5.1"..<"1.0.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", "2.2.0"..<"3.0.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", "4.0.0"..<"5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftLambda",
            dependencies: [
                .product(name: "AWSLambdaHelpers", package: "swift-server-utilities"),
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "NIOHelpers", package: "swift-server-utilities"),
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
            name: "SwiftServerAppTests",
            dependencies: [
                .target(name: "SwiftServerApp")
            ]
        )
    ]
)
