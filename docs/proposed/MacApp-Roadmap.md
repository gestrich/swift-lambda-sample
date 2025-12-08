# MacApp Development Roadmap

This document outlines the steps to enhance the MacApp with API Gateway integration and client code generation.

## Tasks

### [ ] Add API Gateway Client Features to MacApp

Integrate the existing AWS Lambda API endpoints (file upload/download, user CRUD) into the MacApp SwiftUI interface.

**Current API Endpoints:**
- `POST /api/file` - Upload and download S3 test file
- `POST /api/database` - Initialize/reset database
- `GET /api/users` - List all users
- `POST /api/users` - Create user
- `GET /api/users/{uuid}` - Get single user
- `PUT /api/users/{uuid}` - Update user
- `DELETE /api/users/{uuid}` - Delete user

**Implementation Steps:**

1. **Create API Client Service** (`Sources/MacApp/APIClient.swift`)
   - Add URLSession-based HTTP client
   - Store API Gateway base URL (from `swift run SwiftDeploy aws get-url`)
   - Create methods for each endpoint:
     ```swift
     class APIClient {
         let baseURL: String

         func uploadFile() async throws -> String
         func listUsers() async throws -> [User]
         func createUser(_ user: User) async throws -> User
         // ... etc
     }
     ```

2. **Create Model Structs** (`Sources/MacApp/Models.swift`)
   - Define `User` model matching the API schema
   - Make models `Codable` for JSON serialization
   ```swift
   struct User: Codable, Identifiable {
       let id: UUID?
       let email: String
       let firstName: String
       let lastName: String
       let nickName: String?
       let phone: String?
       let slackID: String?
   }
   ```

3. **Add SwiftUI Views**
   - **File Upload View** - Button to test S3 upload/download
   - **User List View** - Display users in a List
   - **User Form View** - Create/edit user form
   - Use `@State` and `async/await` for API calls

4. **Update ContentView**
   - Add TabView or NavigationStack
   - Tabs: "Files", "Users", "Settings"
   - Simple, clean UI

5. **Configuration**
   - Store API Gateway URL in UserDefaults or config file
   - Add settings view to update URL
   - Load from `~/.swiftSampleDemo/api-config.json`

**Example Simple Implementation:**
```swift
// FileView.swift
struct FileView: View {
    @State private var result = ""
    @State private var isLoading = false

    var body: some View {
        VStack {
            Button("Test S3 Upload/Download") {
                Task {
                    isLoading = true
                    do {
                        result = try await APIClient.shared.uploadFile()
                    } catch {
                        result = "Error: \(error)"
                    }
                    isLoading = false
                }
            }
            .disabled(isLoading)

            Text(result)
        }
    }
}
```

---

### [ ] Use Swift OpenAPI Generator Package Plugin

Automatically generate type-safe Swift client code from the API Gateway OpenAPI specification.

**What is Swift OpenAPI Generator?**
- Apple's official tool for generating Swift code from OpenAPI/Swagger specs
- Creates type-safe client code with proper types, request builders, and error handling
- Package plugin that runs during build time

**Implementation Steps:**

1. **Export OpenAPI Spec from API Gateway**
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

2. **Add Swift OpenAPI Generator Dependencies**

   Update `Package.swift`:
   ```swift
   dependencies: [
       // ... existing dependencies
       .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
       .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
       .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
   ]
   ```

3. **Update MacApp Target**
   ```swift
   .executableTarget(
       name: "MacApp",
       dependencies: [
           .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
           .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
       ],
       plugins: [
           .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
       ],
       swiftSettings: [
           .unsafeFlags(["-parse-as-library"])
       ]
   )
   ```

4. **Add OpenAPI Files to MacApp**

   Create `Sources/MacApp/openapi.yaml` (the exported spec from step 1)

   Create `Sources/MacApp/openapi-generator-config.yaml`:
   ```yaml
   generate:
     - types
     - client
   accessModifier: internal
   ```

5. **Use Generated Client**

   The plugin will generate:
   - `Types.swift` - All models (User, etc.)
   - `Client.swift` - API client with all endpoints

   Usage:
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

6. **Benefits of Using OpenAPI Generator**
   - ✅ Type-safe: Compiler catches API mismatches
   - ✅ Auto-complete: Full IDE support
   - ✅ Up-to-date: Re-generate when API changes
   - ✅ Less code: No manual JSON parsing
   - ✅ Error handling: Proper typed errors

**Next Steps After Setup:**
- Export OpenAPI spec from API Gateway
- Add to MacApp sources
- Run `swift build` - plugin auto-generates code
- Replace manual APIClient with generated client
- Enjoy type-safe API calls!

---

## Notes

- Start with manual APIClient (simple, works quickly)
- Migrate to OpenAPI Generator for production (type-safe, maintainable)
- Both approaches work - OpenAPI is more robust for larger projects

## Resources

- [Swift OpenAPI Generator Docs](https://github.com/apple/swift-openapi-generator)
- [API Gateway Export API](https://docs.aws.amazon.com/apigateway/latest/api/API_GetExport.html)
- [SwiftUI Async/Await Patterns](https://developer.apple.com/documentation/swiftui/state-and-data-flow)
