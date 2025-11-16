# Project TODO

This document tracks planned improvements and known issues for the Swift Lambda Sample project.

## Infrastructure & Deployment

- [ ] Ensure a complete CDK teardown and deploy works then document how to go from zero to full deploy and running.
- [ ] Add conditional support for private VPC vs public database (to save on NAT gateway costs)

## Code Quality & Cleanup

- [ ] Remove this fallback logic: `// Read from environment, fallback to hardcoded value for backwards compatibility`
- [ ] Remove this fallback if not needed: `// Fallback: if secret is just a plain string (not JSON), use it directly`
- [ ] Determine why the dynamic value was removed and it was hardcoded here:
  ```diff
  -        POSTGRES_DBNAME: props.database.instanceIdentifier,
  +        POSTGRES_DBNAME: 'FFMSampleLambdaDB'
  ```

## Build & Docker

- [ ] Combine build.sh and build-local.sh into same script
- [ ] Add docs regarding local docker build and deploys - include docker interactive mode
- [ ] For the netrc, ensure that actually works with a real private repo dependency and why we have a "dummy" one committed to repo now.

## Database

- [ ] Ensure local postgres running still works since TLS was enabled here: `let tls = PostgresConnection.Configuration.TLS.prefer(sslContext)`

## GitHub & CI/CD

- [ ] Ensure a complete Github teardown
  - [ ] Delete all Github environment and passwords

## Upgrades

- [ ] Upgrade to Lambda engine v2.

## Documentation

See [PRINCIPLES.md](PRINCIPLES.md) for tracking progress on server development principles.
