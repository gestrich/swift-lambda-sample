# REST API Update Best Practices - Implementation Plan

## Problem Statement

The user update API is currently broken because:

1. **Mac app sends**: `UpdateUserRequest` with `password: nil` (correct)
2. **API handler expects**: `CreateUser` with required `password` field (incorrect)
3. **Result**: Decoding error - "No value associated with key 'password'"

## REST API Update Best Practices

### PUT vs PATCH

**PUT (Full Replacement)**
- Replaces the entire resource
- Should require all fields (except server-managed ones like ID, timestamps)
- Idempotent - same request always produces same result
- Example: Update user with complete data

**PATCH (Partial Update)**
- Updates only specified fields
- Fields not included are left unchanged
- More flexible and common in modern APIs
- Example: Update only email and phone, leave other fields unchanged

### Password Handling Best Practices

1. **CREATE**: Password required
2. **UPDATE**: Password optional (only include if changing password)
3. **READ**: Password never returned (security)
4. **Special field handling**: Empty password should not update

### Current vs Desired State

**Current (Broken)**
```swift
// PUT /api/users/{id}
// Expects: CreateUser with required password
let userRequest = try JSONDecoder().decode(CreateUser.self, from: bodyData)
user.applyCreateUserRequest(userRequest) // Applies ALL fields
```

**Desired (Fixed)**
```swift
// PUT /api/users/{id} with PATCH semantics
// Accepts: UpdateUser with optional fields
let updateRequest = try JSONDecoder().decode(UpdateUser.self, from: bodyData)
user.applyUpdateUserRequest(updateRequest) // Applies only non-nil fields
```

## Implementation Plan

### Step 1: Create UpdateUser DTO

**File**: `Sources/SwiftServerApp/Postgres/UpdateUser.swift` (new file)

```swift
public struct UpdateUser: Codable {
    public var email: String?
    public var password: String?
    public var firstName: String?
    public var lastName: String?
    public var nickName: String?
    public var phone: String?
    public var slackID: String?

    public init(email: String?, password: String?, firstName: String?, lastName: String?, nickName: String?, phone: String?, slackID: String?) {
        self.email = email
        self.password = password
        self.firstName = firstName
        self.lastName = lastName
        self.nickName = nickName
        self.phone = phone
        self.slackID = slackID
    }
}
```

### Step 2: Update API Handler

**File**: `Sources/SwiftLambda/Handlers/APIGatewayHandler.swift`

**Change from:**
```swift
let userRequest = try JSONDecoder().decode(CreateUser.self, from: bodyData)
user.applyCreateUserRequest(userRequest)
```

**Change to:**
```swift
let updateRequest = try JSONDecoder().decode(UpdateUser.self, from: bodyData)
user.applyUpdateUserRequest(updateRequest)
```

### Step 3: Add Update Method to User Extension

**File**: `Sources/SwiftLambda/Handlers/APIGatewayHandler.swift`

Add new method alongside `applyCreateUserRequest`:

```swift
extension User {
    func applyUpdateUserRequest(_ updateUser: UpdateUser) {
        // Only update fields that are provided (non-nil)
        if let email = updateUser.email {
            self.email = email
        }
        if let password = updateUser.password, !password.isEmpty {
            self.password = password
        }
        if let firstName = updateUser.firstName {
            self.firstName = firstName
        }
        if let lastName = updateUser.lastName {
            self.lastName = lastName
        }
        if let nickName = updateUser.nickName {
            self.nickName = nickName
        }
        if let phone = updateUser.phone {
            self.phone = phone
        }
        if let slackID = updateUser.slackID {
            self.slackID = slackID
        }
    }
}
```

### Step 4: Alternative - Use Protocol for Common Interface (Optional Enhancement)

This makes the code more maintainable:

```swift
protocol UserRequestProtocol {
    var email: String? { get }
    var password: String? { get }
    var firstName: String? { get }
    var lastName: String? { get }
    var nickName: String? { get }
    var phone: String? { get }
    var slackID: String? { get }
}

extension CreateUser: UserRequestProtocol {
    var email: String? { email }
    var password: String? { password }
    // ... etc
}

extension UpdateUser: UserRequestProtocol {
    // Already has optional properties
}

extension User {
    func applyUserRequest<T: UserRequestProtocol>(_ request: T, onlyIfPresent: Bool = false) {
        // Unified update logic
    }
}
```

## Benefits of This Approach

✅ **Follows REST best practices**: Partial updates allowed
✅ **Secure**: Password only updated when explicitly provided
✅ **Backward compatible**: Existing clients work unchanged
✅ **Type safe**: Compiler enforces optional handling
✅ **Flexible**: Can update any subset of fields
✅ **Mac app works**: Already sends UpdateUserRequest correctly

## Testing Plan

1. **Create user** - POST with all fields including password ✅
2. **Update user without password** - PUT with other fields, no password ✅
3. **Update user with password** - PUT including new password ✅
4. **Update partial fields** - PUT with only 1-2 fields changed ✅
5. **Empty password** - PUT with empty password should not update ✅

## Alternative Considered: Add PATCH Endpoint

Could add separate PATCH endpoint:
- **PUT** = full replacement (requires all fields)
- **PATCH** = partial update (optional fields)

**Not chosen because:**
- More breaking changes required
- Current API semantics already PATCH-like
- Mac app already expects partial updates on PUT

## Files Modified

1. `Sources/SwiftServerApp/Postgres/UpdateUser.swift` - NEW
2. `Sources/SwiftLambda/Handlers/APIGatewayHandler.swift` - MODIFIED (2 changes)
   - Decode UpdateUser instead of CreateUser (line 172)
   - Add applyUpdateUserRequest extension method (after line 262)

## Summary

This fix:
- Aligns API with REST best practices for partial updates
- Fixes the Mac app user update functionality
- Handles passwords securely (optional on update)
- Minimal code changes (1 new file, 2 modifications)
- Type-safe with clear semantics
