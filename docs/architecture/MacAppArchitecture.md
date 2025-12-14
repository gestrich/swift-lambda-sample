# Mac App Architecture

## Overview

The app follows a **Model-View (MV)** architecture pattern with Services.

## Models

Models hold app state and serve as the API that views interact with.

- Conform to `@Observable`
- Views observe models directly
- Contain minimal business logic
- Delegate work to services
- Can be composed from other models

### AppModel

A top-level `AppModel` serves as the root, composing all domain models.

```swift
@Observable
class AppModel {
    let userModel: UserModel
    let settingsModel: SettingsModel
}
```

### Domain Models

```swift
@Observable
class UserModel {
    private let userService: UserService

    var users: [User] = []
    var isLoading = false

    func loadUsers() async {
        isLoading = true
        users = await userService.fetchUsers()
        isLoading = false
    }
}
```

### Optional Models

Some models are defined as optional. These represent state that only exists after configuration or user action. If the model exists, it is ready to use—avoiding optional values within the model itself.

```swift
@Observable
class AppModel {
    let settingsModel: SettingsModel
    var syncModel: SyncModel?  // Only exists after user configures sync
}
```

## State

State is represented by structs. Services define the state types; models hold the current values.

```swift
struct UserState {
    var users: [User]
    var selectedUser: User?
}
```

## Services

Services are stateless and handle external interactions. They define the state structs they work with.

- Network requests
- Database operations
- File system access
- External APIs

```swift
struct UserService {
    func fetchUsers() async -> [User] {
        // Network call
    }

    func saveUser(_ user: User) async {
        // Database operation
    }
}
```

## Data Flow

```
View → Model → Service → External (Network/DB/etc.)
```

Views observe models. Models call services. Services return data.
