# Running Swift Lambda Locally

This guide has been split into focused documentation for different development approaches:

## Choose Your Development Approach

### 🍎 [Running with Xcode (Mac Development)](RUN_LOCALLY_XCODE.md)

**Best for:**
- Active development with fast iteration
- Debugging with Xcode breakpoints
- Native Mac development experience

**Quick Start:**
```bash
./tools.sh local services start-all  # Start PostgreSQL + MinIO
# Then run in Xcode (⌘R)
```

---

### 🐧 [Building and Running with Linux Containers](RUN_LOCALLY_LINUX.md)

**Best for:**
- Building deployment packages for AWS
- Testing in production-like environment
- Verifying Linux compatibility

**Quick Start:**
```bash
./build.sh SwiftLambda                    # Build for AWS Lambda
./tools.sh local lambda run-container     # Test in Linux container
```

---

## Local Services

Both approaches use the same local services:

### Start Services

```bash
./tools.sh local services start-all
```

This starts:
- **PostgreSQL** on `localhost:5432` (docker/docker/docker)
- **MinIO** (S3) on `localhost:9000` (admin/password)
  - Console: http://localhost:9001

### Stop Services

```bash
./tools.sh local services stop-all
```

### Verify Services

```bash
docker ps
# Should show: postgres_lambda and minio_lambda
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Copy config | `./tools.sh local copy-config` |
| Start services | `./tools.sh local services start-all` |
| Stop services | `./tools.sh local services stop-all` |
| Build for AWS | `./build.sh SwiftLambda` |
| Run in container | `./tools.sh local lambda run-container` |

---

## Next Steps

- **Xcode Development**: See [RUN_LOCALLY_XCODE.md](RUN_LOCALLY_XCODE.md)
- **Linux Containers**: See [RUN_LOCALLY_LINUX.md](RUN_LOCALLY_LINUX.md)
- **AWS Deployment**: See [CLAUDE.md](../CLAUDE.md)
- **Development Principles**: See [PRINCIPLES.md](PRINCIPLES.md)
