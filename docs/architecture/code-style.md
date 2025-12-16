# Code Style

Guidelines for consistent code organization across the project.

## Imports

Order imports alphabetically:

```swift
import Foundation
import sdk_aws
import sdk_cli
import service_deploy
```

## File Organization

Structure files to show the most important elements first:

```swift
struct MyService {
    // 1. Stored properties (most important - what the type holds)
    private let client: APIClient
    private let cache: Cache

    // 2. Initializer (how to create it)
    init(client: APIClient, cache: Cache) {
        self.client = client
        self.cache = cache
    }

    // 3. Computed properties
    var isReady: Bool { client.isConnected }

    // 4. Methods
    func fetch() async throws -> Data { ... }

    // 5. Nested types (enums, structs) at the bottom
    enum State {
        case idle
        case loading
        case loaded(Data)
    }
}
```

**Rationale**: Readers scanning a file want to quickly understand what a type holds and how to create it. Nested type definitions are implementation details that can live at the bottom.

## Avoid Type Aliases and Re-exports

Type aliases and re-exports are a code smell. They obscure the actual types being used and create indirection that makes code harder to follow.

```swift
// Avoid
public typealias ClientResult = Result<Data, ClientError>
@_exported import sdk_aws

// Prefer
// Use the actual types directly
func fetch() -> Result<Data, ClientError>
```

If you find yourself wanting a type alias, consider whether the underlying type should be renamed or if a new type is warranted.
