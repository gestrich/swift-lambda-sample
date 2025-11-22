# Migration to swift-aws-lambda-runtime 2.0

## Overview

This document describes the migration from swift-aws-lambda-runtime v1.x to v2.0, including the implementation of dynamic event routing to support multiple Lambda invocation sources.

## What Changed in 2.0

### Core Architecture Changes

1. **Removed `ByteBufferLambdaHandler`** - The low-level byte buffer handler no longer exists
2. **Removed `EventLoopLambdaHandler`** - Replaced with async/await protocols
3. **Control Inversion** - Developers now own the `@main` function instead of the runtime
4. **Async/Await First** - No more NIO EventLoopFutures and promises
5. **Structured Concurrency** - Uses Swift's modern concurrency features
6. **Availability Macros** - Requires macOS 15.0+ for Lambda 2.0 features

### New Handler Protocols

- **`LambdaHandler`** - Standard handler with typed input/output
- **`LambdaWithBackgroundProcessingHandler`** - Handler with background work support
- **`StreamingLambdaHandler`** - Handler with response streaming support

### Removed Helper Modules

- `AWSLambdaHelpers` - No longer exists
- `NIOHelpers` - No longer exists

## Migration Strategy

### Approach: Union Type Pattern for Dynamic Routing

Since we need to support multiple event sources (API Gateway, CloudWatch, Direct invocations), we implemented a **union type pattern** that:

1. Creates an enum wrapping all possible event types
2. Implements custom `Decodable` to try decoding each type
3. Routes based on the successfully decoded type

### Implementation Details

#### 1. Added AWSLambdaEvents Dependency

```swift
// Package.swift
.package(url: "https://github.com/swift-server/swift-aws-lambda-events.git", from: "0.5.0")

// Added to SwiftLambda target dependencies
.product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events")
```

#### 2. Created LambdaEvent Union Type

**File:** `Sources/SwiftLambda/LambdaEvent.swift`

```swift
public enum LambdaEvent: Decodable {
    case apiGateway(APIGatewayRequest)
    case cloudWatchScheduled(CloudwatchEvent<CloudwatchDetails.Scheduled>)
    case directCreateUser(CreateUser)

    public init(from decoder: Decoder) throws {
        // Try API Gateway first (most common)
        if let apiGatewayRequest = try? APIGatewayRequest(from: decoder) {
            self = .apiGateway(apiGatewayRequest)
            return
        }

        // Try CloudWatch scheduled event
        if let scheduledEvent = try? CloudwatchEvent<CloudwatchDetails.Scheduled>(from: decoder) {
            self = .cloudWatchScheduled(scheduledEvent)
            return
        }

        // Try direct CreateUser invocation
        if let createUser = try? CreateUser(from: decoder) {
            self = .directCreateUser(createUser)
            return
        }

        throw DecodingError.dataCorrupted(...)
    }
}
```

**Key Points:**
- Try decoding in order of likelihood (API Gateway most common)
- Each event type has a discriminating structure that makes decoding unique
- Falls through to next type if decoding fails

#### 3. Updated Main Handler

**File:** `Sources/SwiftLambda/LambdaHandler.swift`

**Old Pattern (v1.x):**
```swift
@main
public struct LambdaHandler: ByteBufferLambdaHandler {
    public func handle(context: Lambda.Context, event: ByteBuffer) -> EventLoopFuture<ByteBuffer?> {
        // Dynamic routing logic
    }
}
```

**New Pattern (v2.0):**
```swift
@main
struct MyLambda {
    static func main() async throws {
        let handler = SwiftLambdaHandler()
        let adapter = LambdaHandlerAdapter(handler: handler)
        let codableAdapter = LambdaCodableAdapter(encoder: JSONEncoder(), decoder: JSONDecoder(), handler: adapter)
        let runtime = LambdaRuntime(handler: codableAdapter)
        try await runtime.run()
    }
}

struct SwiftLambdaHandler: LambdaHandler {
    typealias Event = LambdaEvent
    typealias Output = String

    func handle(_ event: LambdaEvent, context: LambdaContext) async throws -> String {
        switch event {
        case .apiGateway(let request):
            return try await handleAPIGateway(request: request, context: context)
        case .cloudWatchScheduled(let scheduledEvent):
            return try await handleCloudWatchScheduled(event: scheduledEvent, context: context)
        case .directCreateUser(let createUser):
            return try await handleDirectCreateUser(user: createUser, context: context)
        }
    }
}
```

**Key Changes:**
- Explicit `@main` function that initializes runtime
- `LambdaHandler` protocol conformance (not `ByteBufferLambdaHandler`)
- `LambdaHandlerAdapter` wraps handler to support background processing
- `LambdaCodableAdapter` handles JSON encoding/decoding
- Pure async/await - no EventLoopFutures

#### 4. Removed Dynamic Routing Infrastructure

**Deleted Files:**
- `Sources/SwiftLambda/DynamicLambdaHandler.swift` - No longer needed with union type approach

**Why:** The union type pattern via `Decodable` provides the same functionality in a more type-safe way.

#### 5. Updated Handler Implementations

**APIGWHandler Changes:**

```swift
// Old
struct APIGWHandler: EventLoopLambdaHandler {
    func handle(context: Lambda.Context, event: APIGateway.Request) -> EventLoopFuture<APIGateway.Response> {
        return context.eventLoop.asyncFuture { ... }
    }
}

// New
struct APIGWHandler {
    func handle(context: LambdaContext, event: APIGatewayRequest) async throws -> APIGatewayResponse {
        // Direct async/await - no EventLoopFuture
    }
}
```

**Type Changes:**
- `Lambda.Context` → `LambdaContext`
- `APIGateway.Request` → `APIGatewayRequest`
- `APIGateway.Response` → `APIGatewayResponse`
- `HTTPResponseStatus` → `HTTPResponse.Status`
- `.POST` → `.post` (lowercase HTTP methods)
- `event.bodyData()` → `event.body` (now a `String?`, convert to `Data` manually)

**CreateUserHandler Changes:**

```swift
// Old
public struct CreateUserHandler: EventLoopLambdaHandler {
    public func handle(context: Lambda.Context, event: In) -> EventLoopFuture<Out> { ... }
}

// New
public struct CreateUserHandler {
    func handle(context: LambdaContext, event: CreateUser) async throws -> String {
        // Direct async/await
    }
}
```

#### 6. Refactored ServiceComposer

**Challenge:** Fluent/Postgres requires NIO EventLoop, but `LambdaContext` no longer exposes one.

**Solution:** Create EventLoop internally when needed (only for database operations).

```swift
class ServiceComposer {
    let eventLoopGroup: MultiThreadedEventLoopGroup?

    init() async throws {
        // Create EventLoopGroup only if database is configured
        let hasDatabase = (try? await configurationService.postgresConfiguration()) != nil
        if hasDatabase {
            eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        } else {
            eventLoopGroup = nil
        }

        // Pass eventLoopGroup.next() to UserStorePostgres when needed
    }

    func shutdown() async throws {
        try await awsClient.shutdown()
        try await userStoreService.shutdown()
        try await eventLoopGroup?.shutdownGracefully()
    }
}
```

**Key Points:**
- EventLoop is optional - only created when database is used
- Properly shut down during cleanup
- Isolated to database layer - doesn't leak into handler code

#### 7. CloudWatch Scheduled Event Handler

**New Functionality:** Write timestamped file to S3 when CloudWatch event fires.

```swift
private func handleCloudWatchScheduled(event: CloudwatchEvent<CloudwatchDetails.Scheduled>, context: LambdaContext) async throws -> String {
    context.logger.info("CloudWatch scheduled event received")

    let services = try await ServiceComposer()
    defer { Task { try? await services.shutdown() } }

    let timestamp = ISO8601DateFormatter().string(from: event.time)
    let content = "CloudWatch scheduled event fired at \(timestamp)\nEvent ID: \(event.id)"

    try await services.app.uploadToS3(key: "scheduled-event-\(timestamp).txt", content: content)

    return "CloudWatch scheduled event processed successfully - file written to S3"
}
```

**Added Helper Method:**

```swift
// SwiftServerApp.swift
public func uploadToS3(key: String, content: String) async throws {
    guard let cloudDataStore else {
        throw LambdaDemoError.missingService(name: "s3Service")
    }
    guard let data = content.data(using: .utf8) else {
        throw LambdaDemoError.unexpectedError(description: "Failed to convert string to data")
    }
    try await cloudDataStore.uploadData(data, key: key)
}
```

#### 8. Updated CDK Configuration

**File:** `cdk/lib/constructs/monitoring-construct.ts`

**Old (Custom Payload):**
```typescript
this.eventRule.addTarget(
  new targets.LambdaFunction(props.lambdaFunction, {
    event: events.RuleTargetInput.fromObject({
      appName: props.appName,
      releaseLookbackHours: props.releaseLookbackHours
    })
  })
);
```

**New (Standard CloudWatch Event):**
```typescript
// CloudWatch will send a standard scheduled event (no custom payload)
this.eventRule.addTarget(
  new targets.LambdaFunction(props.lambdaFunction)
);
```

**Why:** CloudWatch now sends standard `CloudwatchEvent<CloudwatchDetails.Scheduled>` which our union type can decode.

#### 9. Updated Package Configuration

**File:** `Package.swift`

```swift
// Updated minimum platform
platforms: [
    .macOS("15.0")  // Was 13.0
]

// Added dependency
.package(url: "https://github.com/swift-server/swift-aws-lambda-events.git", from: "0.5.0")
```

## Event Type Discrimination

### How Events Are Distinguished

**API Gateway Request:**
- Has `requestContext` field
- Has `httpMethod` field
- Structure unique to API Gateway

**CloudWatch Scheduled Event:**
- Has `source` field (set to "aws.events")
- Has `detail-type` field (set to "Scheduled Event")
- Has `detail` field (empty for scheduled events)

**Direct CreateUser Invocation:**
- Has `email`, `password`, `firstName`, etc. fields
- Structure unique to CreateUser model

### Decoding Order Matters

```swift
// 1. Try API Gateway first (most common in production)
// 2. Try CloudWatch second (scheduled tasks)
// 3. Try CreateUser last (direct invocations)
```

This ordering optimizes for the most common case while ensuring all types can be decoded.

## Testing Strategy

### 1. API Gateway Routing Test

```bash
# Test file upload endpoint (no database required)
curl -X POST https://{api-id}.execute-api.us-east-1.amazonaws.com/prod/api/file

# Expected: "File uploaded and downloaded"
```

### 2. CloudWatch Scheduled Event Test

```bash
# List files in S3 bucket
aws s3 ls s3://{bucket-name}/ --profile production

# Expected: Files named scheduled-event-{timestamp}.txt

# Download and view
aws s3 cp s3://{bucket-name}/scheduled-event-{timestamp}.txt - --profile production
```

### 3. Check Lambda Logs

```bash
aws logs tail /aws/lambda/swift-lambda-sample \
  --since 5m \
  --profile production

# Look for:
# - "CloudWatch scheduled event received"
# - "Successfully wrote scheduled event file to S3"
```

### 4. Monitor GitHub Actions

```bash
gh run list --repo gestrich/swift-lambda-sample --branch dev --limit 1
gh run view --repo gestrich/swift-lambda-sample --log
```

## Deployment Process

### Minimal Cost Deployment (No Database, No NAT)

```bash
# Tear down existing stack
swift run SwiftDeploy tear-down

# Fresh deployment (minimal cost)
swift run SwiftDeploy deploy-full

# This deploys:
# - Lambda function (in AWS-managed VPC)
# - API Gateway (public endpoint)
# - S3 bucket
# - SQS queues
# - CloudWatch scheduled event rule
# - No VPC
# - No NAT Gateway
# - No Database
```

### With Database (Optional)

```bash
# Deploy with PostgreSQL
swift run SwiftDeploy deploy-full --with-postgres

# Full deployment with NAT Gateway
swift run SwiftDeploy deploy-full --with-postgres --with-nat-gateway
```

## Breaking Changes Summary

| Old (v1.x) | New (v2.0) |
|------------|------------|
| `ByteBufferLambdaHandler` | `LambdaHandler` with `LambdaCodableAdapter` |
| `EventLoopLambdaHandler` | `LambdaHandler` |
| `Lambda.Context` | `LambdaContext` |
| `EventLoopFuture<T>` | `async throws -> T` |
| `context.eventLoop` | Not available (create own if needed) |
| `APIGateway.Request` | `APIGatewayRequest` |
| `APIGateway.Response` | `APIGatewayResponse` |
| `HTTPResponseStatus` | `HTTPResponse.Status` |
| `.POST`, `.GET` | `.post`, `.get` (lowercase) |
| `event.bodyData()` | `event.body` (String?) |
| `AWSLambdaHelpers` | Removed |
| `NIOHelpers` | Removed |
| Runtime owns `main` | Developer owns `@main` |

## Benefits of Migration

1. **Modern Swift** - Uses async/await and structured concurrency
2. **Type Safety** - Union type pattern provides compile-time safety
3. **Cleaner Code** - No EventLoopFuture bridging
4. **Better Error Handling** - Async/await error handling is clearer
5. **Flexibility** - Can easily add new event types to union
6. **Performance** - Less overhead from EventLoop when not needed

## Future Considerations

### Adding New Event Types

To add a new event source (e.g., S3 event):

1. Add case to `LambdaEvent` enum
2. Add decoding logic in `init(from:)`
3. Add handler method
4. Add switch case in main handler

Example:
```swift
public enum LambdaEvent: Decodable {
    case apiGateway(APIGatewayRequest)
    case cloudWatchScheduled(CloudwatchEvent<CloudwatchDetails.Scheduled>)
    case s3Event(S3Event)  // New
    case directCreateUser(CreateUser)

    public init(from decoder: Decoder) throws {
        // ... existing cases ...

        if let s3Event = try? S3Event(from: decoder) {
            self = .s3Event(s3Event)
            return
        }

        // ... remaining cases ...
    }
}
```

### Response Type Flexibility

Currently all handlers return `String`. To support different response types per event:

```swift
enum LambdaResponse: Encodable {
    case apiGateway(APIGatewayResponse)
    case string(String)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .apiGateway(let response):
            try response.encode(to: encoder)
        case .string(let string):
            var container = encoder.singleValueContainer()
            try container.encode(string)
        }
    }
}
```

## References

- [swift-aws-lambda-runtime 2.0 Release](https://github.com/swift-server/swift-aws-lambda-runtime/releases)
- [swift-aws-lambda-events](https://github.com/swift-server/swift-aws-lambda-events)
- [AWS Lambda V2 API Proposal](https://forums.swift.org/t/aws-lambda-v2-api-proposal/73819)
- [What's New in Lambda V2](https://swifttoolkit.dev/posts/lambda-v2)

## Migration Completed

**Date:** 2025-01-16
**Swift Version:** 6.2
**Runtime Version:** 2.3.1
**Events Version:** 0.5.0+

✅ All compilation errors resolved
✅ Dynamic event routing implemented
✅ CloudWatch scheduled events configured
✅ S3 write functionality added
✅ Ready for deployment and testing
