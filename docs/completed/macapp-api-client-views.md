# MacApp API Client Views

## Status: Complete

## Goal

Integrate the existing AWS Lambda API endpoints (file upload/download, user CRUD, reminders) into the MacApp SwiftUI interface using a manual HTTP client.

## Implementation Summary

All phases completed. The implementation includes more features than originally planned, including DynamoDB reminders support.

## Current API Endpoints

- `POST /api/files` - Upload file (with base64 data)
- `GET /api/files` - List all files
- `GET /api/files/{fileName}` - Download file
- `DELETE /api/files/{fileName}` - Delete file
- `POST /api/database` - Initialize/reset database
- `GET /api/users` - List all users
- `POST /api/users` - Create user
- `GET /api/users/{uuid}` - Get single user
- `PUT /api/users/{uuid}` - Update user
- `DELETE /api/users/{uuid}` - Delete user
- `GET /api/reminders` - List all reminders
- `POST /api/reminders` - Create reminder
- `GET /api/reminders/{id}` - Get reminder
- `PUT /api/reminders/{id}` - Update reminder
- `DELETE /api/reminders/{id}` - Delete reminder

## Implementation Phases

### Phase 1: Create API Client Service

**File:** `Sources/services/ClientService/APIClient.swift`

- [x] Add URLSession-based HTTP client
- [x] Store API Gateway base URL
- [x] Support both remote (API Gateway) and local (Lambda) modes
- [x] Create methods for all endpoints (files, users, reminders)

### Phase 2: Create Model Structs

**Files in `Sources/services/ClientService/`:**

- [x] `User.swift` - User model with Codable conformance
- [x] `CreateUserRequest.swift` / `UpdateUserRequest.swift` - Request types
- [x] `Reminder.swift` - Reminder model for DynamoDB
- [x] `CreateReminderRequest.swift` / `UpdateReminderRequest.swift` - Request types
- [x] `FileUploadRequest.swift` / `FileDownloadResponse.swift` - S3 types

### Phase 3: Add SwiftUI Views

**Files in `Sources/apps/MacApp/UI/Client/`:**

- [x] `S3View.swift` - File upload/download/delete with image preview
- [x] `PostgresView.swift` - User list with CRUD operations
- [x] `UserFormView.swift` - Create/edit user form
- [x] `RemindersView.swift` - Reminder list with CRUD operations
- [x] `ReminderFormView.swift` (embedded) - Create/edit reminder
- [x] `ClientView.swift` - Main container with all sections

### Phase 4: Update ContentView

- [x] ClientView organized with GroupBox sections
- [x] Sections: Files (S3), Reminders (DynamoDB), Users (PostgreSQL)
- [x] Clean, consistent UI

### Phase 5: Configuration

- [x] baseURL configurable per APIClient instance
- [x] Support for multiple service connections (Xcode, Linux, Remote)
- [x] serviceName property identifies which deployment created data

## Files Created

| File | Description |
|------|-------------|
| `Sources/services/ClientService/APIClient.swift` | HTTP client with remote/local modes |
| `Sources/services/ClientService/User.swift` | User model |
| `Sources/services/ClientService/Reminder.swift` | Reminder model |
| `Sources/services/ClientService/*.swift` | Request/response types |
| `Sources/apps/MacApp/UI/Client/ClientView.swift` | Main container view |
| `Sources/apps/MacApp/UI/Client/S3View.swift` | S3 file operations |
| `Sources/apps/MacApp/UI/Client/PostgresView.swift` | User CRUD |
| `Sources/apps/MacApp/UI/Client/UserFormView.swift` | User form |
| `Sources/apps/MacApp/UI/Client/RemindersView.swift` | Reminder CRUD |
| `Sources/apps/MacApp/UI/Client/APIClient+Previews.swift` | Preview helpers |

## Features Beyond Original Plan

1. **DynamoDB Reminders** - Full CRUD for reminders with due dates
2. **Local Lambda Mode** - APIClient wraps requests for local `/invoke` endpoint
3. **Multi-service Support** - Can connect to Xcode, Linux, or Remote deployments
4. **Image Preview** - Preview images directly in S3View
5. **Sample User Creation** - Quick test user creation per service
6. **Error Handling** - Detailed error messages with raw response display

## Related

- [OpenAPI Client Generation](openapi-client-generation.md) - Future type-safe alternative
