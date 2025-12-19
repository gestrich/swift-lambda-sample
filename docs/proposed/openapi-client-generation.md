# OpenAPI Client Generation

## Status: Proposed

## Goal

Automatically generate type-safe Swift client code from the API Gateway OpenAPI specification using Apple's Swift OpenAPI Generator.

## Background

**What is Swift OpenAPI Generator?**
- Apple's official tool for generating Swift code from OpenAPI/Swagger specs
- Creates type-safe client code with proper types, request builders, and error handling
- Package plugin that runs during build time

**Benefits:**
- Type-safe: Compiler catches API mismatches
- Auto-complete: Full IDE support
- Up-to-date: Re-generate when API changes
- Less code: No manual JSON parsing
- Error handling: Proper typed errors

## Implementation Steps

### Phase 1: Export OpenAPI Spec from API Gateway

- [ ] Get API ID and export spec

```bash
# Get the API ID
API_ID=$(aws apigateway get-rest-apis \
  --profile production \
  --query 'items[?name==`SwiftLambdaSampleAPI`].id' \
  --output text)

# Export OpenAPI spec
aws apigateway get-export \
  --rest-api-id $API_ID \
  --stage-name prod \
  --export-type oas30 \
  --profile production \
  openapi.yaml
```

### Phase 2: Add Swift OpenAPI Generator Dependencies

- [ ] Update `Package.swift`:

```swift
dependencies: [
    // ... existing dependencies
    .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
]
```

### Phase 3: Update MacApp Target

- [ ] Add dependencies and plugin to MacApp target:

```swift
.executableTarget(
    name: "MacApp",
    dependencies: [
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
        .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
    ],
    plugins: [
        .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
    ]
)
```

### Phase 4: Add OpenAPI Files to MacApp

- [ ] Create `Sources/apps/MacApp/openapi.yaml` (the exported spec from Phase 1)

- [ ] Create `Sources/apps/MacApp/openapi-generator-config.yaml`:

```yaml
generate:
  - types
  - client
accessModifier: internal
```

### Phase 5: Use Generated Client

The plugin will generate:
- `Types.swift` - All models (User, etc.)
- `Client.swift` - API client with all endpoints

- [ ] Update views to use generated client:

```swift
import OpenAPIRuntime
import OpenAPIURLSession

let client = Client(
    serverURL: URL(string: "https://your-api.execute-api.us-east-1.amazonaws.com/prod")!,
    transport: URLSessionTransport()
)

// Type-safe API calls!
let users = try await client.getUsers()
let newUser = try await client.createUser(body: .json(user))
```

### Phase 6: Replace Manual APIClient (if exists)

- [ ] Remove manual `APIClient.swift` if previously created
- [ ] Update all views to use generated client
- [ ] Remove manual model definitions (use generated types)

## Files to Create/Modify

| File | Change |
|------|--------|
| `Package.swift` | Add OpenAPI dependencies and plugin |
| `Sources/apps/MacApp/openapi.yaml` | New - OpenAPI spec from API Gateway |
| `Sources/apps/MacApp/openapi-generator-config.yaml` | New - Generator config |
| `Sources/apps/MacApp/UI/Client/*.swift` | Update to use generated client |

## Success Criteria

1. `swift build` successfully generates client code
2. Generated types match API schema
3. Views use type-safe generated client
4. Compiler catches API mismatches

## Resources

- [Swift OpenAPI Generator Docs](https://github.com/apple/swift-openapi-generator)
- [API Gateway Export API](https://docs.aws.amazon.com/apigateway/latest/api/API_GetExport.html)
- [OpenAPI Runtime](https://github.com/apple/swift-openapi-runtime)

## Notes

- This is more robust than manual APIClient for larger projects
- Requires exporting OpenAPI spec whenever API changes
- Consider automating spec export in CI/CD

## Related

- [MacApp API Client Views](macapp-api-client-views.md) - Manual approach
