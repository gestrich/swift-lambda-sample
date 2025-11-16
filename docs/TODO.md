# Project TODO

This document tracks planned improvements and known issues for the Swift Lambda Sample project.


## Code Quality & Cleanup

- [ ] Swap SOTO for AWS SDK Swift: https://github.com/awslabs/aws-sdk-swift

## Build & Docker

- [ ] Combine build.sh and build-local.sh into same script
- [ ] Add docs regarding local docker build and deploys - include docker interactive mode
- [ ] Clarify the differences running from Xcode vs in Docker container (setup differneces?)
- [ ] For the netrc, ensure that actually works with a real private repo dependency and why we have a "dummy" one committed to repo now.
- [ ] Deterine why PostgresDockerfile is using this archived url: https://apt-archive.postgresql.org/pub/repos/apt

## Database

- [x] Ensure local postgres running still works since TLS was enabled here: `let tls = PostgresConnection.Configuration.TLS.prefer(sslContext)`
  **Resolution**: The `TLS.prefer` mode is correct and works for both environments:
  - **Local Postgres** (no SSL): Attempts TLS, falls back to unencrypted connection
  - **AWS RDS** (requires SSL): Successfully uses TLS connection
  - [ ] DynamoDB Support

## GitHub & CI/CD

- [ ] Ensure a complete Github teardown
- [ ] Delete all Github environment and passwords

## Documentation

See [PRINCIPLES.md](PRINCIPLES.md) for tracking progress on server development principles.
