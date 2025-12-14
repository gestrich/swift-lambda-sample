# Roadmap

This document tracks planned improvements, known issues, and testing checklists for the Swift Lambda Sample project.

## Release V1

- [ ] Learn Views
- [ ] Setup Views - include status buttons and do-for-me. Ensure both nvm, brew, and binary installs work
- [ ] Validate clean install experience (Both mac and CLI pathways)
    - Add DynamoDB local instance
- [ ] README and DocC - Use Claude commands to maintain these. Add screenshots to README
- [ ] Video
- [ ] Social Media Share (LinkedIn, Swift Open Source Slack, others?)

## Clean Install Experience

Need to verify the clean install experience works end-to-end. Test checklist:

### Pre-requisites to Remove

- [ ] Delete remote repo & recreate
- [ ] Delete and reclone repo
- [ ] `rm -rf ~/.swiftSampleDemo/`
- [ ] Delete AWS CLI
- [ ] Delete CDK
- [ ] Delete & Reinstall Docker.app
  - Use official uninstall instructions to avoid issues with incomplete uninstall and stuck startup: https://docs.docker.com/desktop/uninstall/
  - Settings
    - General
      - Apple Virtualization framework: Select
      - Rosetta: Select
    - Resources
      - CPU Limit: 16
      - Memory Limit: 64 GB
      - Swap: 4 GB
      - Disk Usage Limit: 936 GB
- [ ] OIDC

### Test Steps

TODO: Document the steps to verify fresh install works correctly.

## Code Quality & Cleanup

- [ ] Swap SOTO for AWS SDK Swift: https://github.com/awslabs/aws-sdk-swift

## Build & Docker

- [ ] Combine build.sh and build-local.sh into same script
- [ ] Add docs regarding local docker build and deploys - include docker interactive mode
- [ ] Clarify the differences running from Xcode vs in Docker container (setup differences?)
- [ ] For the netrc, ensure that actually works with a real private repo dependency and why we have a "dummy" one committed to repo now.
- [ ] Determine why PostgresDockerfile is using this archived url: https://apt-archive.postgresql.org/pub/repos/apt

## Database

- [x] Ensure local postgres running still works since TLS was enabled here: `let tls = PostgresConnection.Configuration.TLS.prefer(sslContext)`
  **Resolution**: The `TLS.prefer` mode is correct and works for both environments:
  - **Local Postgres** (no SSL): Attempts TLS, falls back to unencrypted connection
  - **AWS RDS** (requires SSL): Successfully uses TLS connection
- [ ] DynamoDB Support

## GitHub & CI/CD

- [ ] Ensure a complete Github teardown
- [ ] Delete all Github environment and passwords

## SwiftDeployCLI

- [ ] Make parity between CLI commands and Mac app

## CLIKit

- [ ] Support collecting all input/output for a single call to be used for generating bash scripts

## SwiftLambda

- [ ] Vend client models from APIGW rather than fluent models
- [ ] Add bash scripts that reflect MacApp Steps

## MacApp

- [ ] Add first run experience
- [ ] Add principles tab

## Documentation

- [ ] README cleanup - consider a Claude code command to maintain this
- [ ] CLAUDE.md cleanup - consider a Claude code command to maintain this
- [ ] Delete old markdowns in docs/
