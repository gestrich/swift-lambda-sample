# Project TODO

This document tracks planned improvements and known issues for the Swift Lambda Sample project.


## Code Quality & Cleanup

- [x] Remove this fallback logic: `// Read from environment, fallback to hardcoded value for backwards compatibility`
- [x] Remove this fallback if not needed: `// Fallback: if secret is just a plain string (not JSON), use it directly`
- [x] Determine why the dynamic value was removed and it was hardcoded here:
  ```diff
  -        POSTGRES_DBNAME: props.database.instanceIdentifier,
  +        POSTGRES_DBNAME: 'FFMSampleLambdaDB'
  ```
  **Resolution**: The hardcoded value is CORRECT. There's an important distinction:
  - `instance.instanceIdentifier` = AWS resource name (e.g., "swiftlambdasamplestack-databaseinstance...")
  - `databaseName` = Actual PostgreSQL database name inside the instance ('FFMSampleLambdaDB')

  PostgreSQL connections require the database name, not the AWS instance identifier.
  The value matches what's set in `swift-lambda-stack.ts:81` when creating the database.

## Build & Docker

- [ ] Combine build.sh and build-local.sh into same script
- [ ] Add docs regarding local docker build and deploys - include docker interactive mode
- [ ] For the netrc, ensure that actually works with a real private repo dependency and why we have a "dummy" one committed to repo now.

## Database

- [x] Ensure local postgres running still works since TLS was enabled here: `let tls = PostgresConnection.Configuration.TLS.prefer(sslContext)`
  **Resolution**: The `TLS.prefer` mode is correct and works for both environments:
  - **Local Postgres** (no SSL): Attempts TLS, falls back to unencrypted connection
  - **AWS RDS** (requires SSL): Successfully uses TLS connection

  Added clarifying comments in PostgresModelStore.swift to document this behavior.

## GitHub & CI/CD

- [ ] Ensure a complete Github teardown
  - [ ] Delete all Github environment and passwords

## Documentation

See [PRINCIPLES.md](PRINCIPLES.md) for tracking progress on server development principles.
