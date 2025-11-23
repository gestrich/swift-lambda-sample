# Deploy Command Refactoring Plan

## Problem Statement

The current `deploy` and `deploy-full` commands both accept `--with-postgres` and `--with-nat-gateway` flags. This creates a dangerous situation where forgetting to pass flags on a subsequent deployment can accidentally delete infrastructure.

### Current Danger Scenario
```bash
# First deployment
./tools.sh aws deploy-full --with-postgres
# ✅ Creates database

# Later (forgot the flag!)
./tools.sh aws deploy
# ❌ CDK sees skipPostgres=true (default)
# ❌ CloudFormation DELETES the database!
```

### Root Cause

CDK uses **context parameters** that are read on every deployment. Missing context defaults to minimal configuration, which triggers resource deletion.

## Proposed Solution

### Command Structure Changes

Rename and restructure commands to have clear, distinct purposes:

| Command | Purpose | Flags | Behavior |
|---------|---------|-------|----------|
| `deploy-init` (renamed from `deploy-full`) | **Set initial configuration** | `--with-postgres`, `--with-nat-gateway` | Declarative: create infrastructure with specified config |
| `deploy` | **Maintain current state** | None (removes postgres/NAT flags) | Queries AWS and maintains existing configuration |

### Key Principles

1. **`deploy-init`** = Declarative (I want this configuration)
   - Only command that accepts infrastructure flags
   - Used for initial deployment or major infrastructure changes
   - Validates against existing stack to prevent accidental deletions

2. **`deploy`** = Maintenance (keep it the same)
   - Queries CloudFormation to detect current configuration
   - Redeploys with same configuration
   - Safe for routine infrastructure updates
   - AWS is the source of truth

## Implementation Plan

### Step 1: Add CloudFormation Query Method

**File:** `Sources/SwiftDeploy/Services/AWSCLIService.swift`

Add method to query stack resources:

```swift
/// Describes stack resources to detect what's deployed
public func describeStackResources(
    name: String
) async throws -> [StackResource] {
    let result = try await execute(
        command: "aws",
        arguments: [
            "cloudformation", "describe-stack-resources",
            "--stack-name", name,
            "--profile", awsConfig.profileName
        ]
    )

    // Parse JSON response
    // Return list of resources with logicalResourceId, resourceType, resourceStatus
}

public struct StackResource {
    let logicalResourceId: String
    let resourceType: String
    let resourceStatus: String
}
```

### Step 2: Add Deployed State Detection

**File:** `Sources/SwiftDeploy/DeploymentService.swift`

Add state detection logic:

```swift
/// Detected state of deployed infrastructure
public struct DeployedState {
    let hasDatabase: Bool
    let hasNATGateway: Bool
    let hasVPC: Bool
}

/// Query AWS to determine what's currently deployed
private func queryDeployedState(
    stackName: String = "SwiftLambdaSampleStack"
) async throws -> DeployedState? {
    do {
        let resources = try await awsService.describeStackResources(name: stackName)

        return DeployedState(
            hasDatabase: resources.contains {
                $0.logicalResourceId.contains("Database") &&
                $0.resourceType.contains("RDS")
            },
            hasNATGateway: resources.contains {
                $0.resourceType == "AWS::EC2::NatGateway"
            },
            hasVPC: resources.contains {
                $0.resourceType == "AWS::EC2::VPC"
            }
        )
    } catch {
        // Stack doesn't exist yet
        return nil
    }
}
```

### Step 3: Update `deploy()` to Query and Maintain State

**File:** `Sources/SwiftDeploy/DeploymentService.swift`

Modify the deploy method:

```swift
/// Deploy CDK stack (maintains current configuration)
public func deploy(options: DeploymentOptions) async throws {
    print("\n📦 Starting CDK deployment...")

    // Query current deployed state
    let deployedState = try await queryDeployedState()

    // Determine what to deploy based on current state
    let finalOptions: DeploymentOptions

    if let state = deployedState {
        // Stack exists - maintain current configuration
        print("\n📊 Detected existing stack configuration:")
        print("   Database: \(state.hasDatabase ? "YES" : "NO")")
        print("   NAT Gateway: \(state.hasNATGateway ? "YES" : "NO")")
        print("   → Maintaining current configuration\n")

        finalOptions = DeploymentOptions(
            skipPostgres: !state.hasDatabase,
            skipNATGateway: !state.hasNATGateway,
            awsProfile: options.awsProfile,
            cdkDirectory: options.cdkDirectory
        )
    } else {
        // No stack exists - use minimal config
        print("\n⚠️  No existing stack detected")
        print("   → Using minimal configuration (no database, no NAT)")
        print("   → Use 'deploy-init' to set initial configuration\n")

        finalOptions = options
    }

    // Build TypeScript first
    try await cdkService.build()

    // Deploy with resolved options
    let cdkOptions = CDKService.DeployOptions(
        skipPostgres: finalOptions.skipPostgres,
        skipNATGateway: finalOptions.skipNATGateway,
        requireApproval: false
    )

    try await cdkService.deploy(options: cdkOptions)

    print("\n✅ CDK deployment completed successfully")
}
```

### Step 4: Rename `deployFull` to `deployInit`

**File:** `Sources/SwiftDeploy/DeploymentService.swift`

Rename and add validation:

```swift
/// Initial deployment workflow - sets infrastructure configuration
/// Use this for first deployment or when changing infrastructure scope
public func deployInit(
    options: DeploymentOptions,
    withPostgres: Bool,
    skipPush: Bool = false,
    stackName: String = "SwiftLambdaSampleStack"
) async throws {
    // Check if stack already exists
    let existingState = try await queryDeployedState(stackName: stackName)

    if let state = existingState {
        print("\n⚠️  WARNING: Stack already exists!")
        print("   Current configuration:")
        print("     Database: \(state.hasDatabase ? "YES" : "NO")")
        print("     NAT Gateway: \(state.hasNATGateway ? "YES" : "NO")")
        print("\n   New configuration:")
        print("     Database: \(withPostgres ? "YES" : "NO")")
        print("     NAT Gateway: \(!options.skipNATGateway ? "YES" : "NO")")

        // Prevent accidental database deletion
        if state.hasDatabase && options.skipPostgres {
            print("\n❌ ERROR: This would DELETE your database!")
            print("   Use 'tear-down' first if you want to remove the database.")
            throw CLIError.invalidConfiguration("Cannot remove database with deploy-init")
        }

        print("\n   Updating existing stack...\n")
    }

    // 1. Deploy infrastructure
    _ = try await deployInfrastructure(options: options, stackName: stackName)

    // 2. Deploy Lambda code
    try await updateLambdaCode(skipPush: skipPush)

    // 3. Initialize database if PostgreSQL was deployed
    if withPostgres {
        try await initializeDatabase(stackName: stackName)
    }

    // 4. Verify deployment
    try await verifyDeployment(stackName: stackName, withPostgres: withPostgres)

    print("\n🎉 Deployment completed successfully!")
}
```

### Step 5: Update CLI Commands

**File:** `Sources/SwiftDeployCLI/AWSCommand.swift`

Update command structure:

```swift
struct AWSCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aws",
        abstract: "AWS deployment and management",
        subcommands: [
            DeployInitCommand.self,  // RENAMED from DeployFullCommand
            DeployCommand.self,       // MODIFIED (flags removed)
            UpdateLambdaCommand.self,
            TearDownCommand.self,
            StatusCommand.self,
            GetURLCommand.self,
            LogsCommand.self,
            TestCommand.self
        ]
    )
}

// NEW: deploy-init command
struct DeployInitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deploy-init",
        abstract: "Initial deployment - set infrastructure configuration"
    )

    @Flag(name: .long, help: "Include PostgreSQL database (~$15/month)")
    var withPostgres = false

    @Flag(name: .long, help: "Include NAT Gateway (~$32/month)")
    var withNatGateway = false

    @Flag(name: .long, help: "Skip git push")
    var skipPush = false

    @Option(name: .long, help: "AWS profile to use")
    var awsProfile: String?

    @Option(name: .long, help: "CDK directory path")
    var cdkDirectory: String = "cdk"

    func run() async throws {
        let config = try loadAWSConfig(profileOverride: awsProfile)
        let projectRoot = FileManager.default.currentDirectoryPath

        let deploymentService = DeploymentService(
            projectRoot: projectRoot,
            awsConfig: config,
            cdkDirectory: cdkDirectory
        )

        let options = DeploymentOptions(
            skipPostgres: !withPostgres,
            skipNATGateway: !withNatGateway,
            awsProfile: config.profileName,
            cdkDirectory: cdkDirectory
        )

        try await deploymentService.deployInit(
            options: options,
            withPostgres: withPostgres,
            skipPush: skipPush
        )
    }
}

// UPDATED: deploy command (postgres/NAT flags REMOVED)
struct DeployCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deploy",
        abstract: "Deploy infrastructure (maintains current configuration)"
    )

    // FLAGS REMOVED:
    // - --with-postgres
    // - --with-nat-gateway

    @Option(name: .long, help: "AWS profile to use")
    var awsProfile: String?

    @Option(name: .long, help: "CDK directory path")
    var cdkDirectory: String = "cdk"

    func run() async throws {
        let config = try loadAWSConfig(profileOverride: awsProfile)
        let projectRoot = FileManager.default.currentDirectoryPath

        let deploymentService = DeploymentService(
            projectRoot: projectRoot,
            awsConfig: config,
            cdkDirectory: cdkDirectory
        )

        // Options are minimal - actual config comes from querying AWS
        let options = DeploymentOptions(
            skipPostgres: true,  // Will be overridden by queryDeployedState()
            skipNATGateway: true,
            awsProfile: config.profileName,
            cdkDirectory: cdkDirectory
        )

        try await deploymentService.deploy(options: options)
    }
}
```

### Step 6: Update tools.sh Wrapper

**File:** `tools.sh`

No changes needed - it just delegates to SwiftDeploy CLI.

### Step 7: Update Documentation

**Files to Update:**
- `CLAUDE.md` - Update all deploy examples
- `README.md` - Update deployment instructions
- `cdk/README.md` - Update CDK deployment docs

## Usage Examples

### Initial Deployment - Minimal (No Database)

```bash
./tools.sh aws deploy-init
```

**Output:**
```
💰 MINIMAL COST MODE:
   - No VPC (Lambda in AWS-managed VPC)
   - No NAT Gateway
   - No Database
   - Cost: ~$0/month

📦 Starting CDK deployment...
🔨 Building CDK TypeScript...
🚀 Deploying CDK stack...
✅ CDK deployment completed successfully
```

### Initial Deployment - With PostgreSQL

```bash
./tools.sh aws deploy-init --with-postgres
```

**Output:**
```
💰 PUBLIC DATABASE MODE (NO NAT):
   - Lambda in AWS-managed VPC (public)
   - Public RDS PostgreSQL database
   - Cost: ~$15-30/month

📦 Starting CDK deployment...
🔨 Building CDK TypeScript...
🚀 Deploying CDK stack...
✅ CDK deployment completed successfully
🗄️  Initializing database...
✅ Deployment completed successfully!
```

### Initial Deployment - Full (Postgres + NAT)

```bash
./tools.sh aws deploy-init --with-postgres --with-nat-gateway
```

**Output:**
```
💰 FULL DEPLOYMENT MODE:
   - VPC with NAT Gateway
   - Private RDS PostgreSQL database
   - Cost: ~$47-62/month

📦 Starting CDK deployment...
✅ Deployment completed successfully!
```

### Maintenance Deployment (Any Configuration)

```bash
./tools.sh aws deploy
```

**Output (if database exists):**
```
📦 Starting CDK deployment...

📊 Detected existing stack configuration:
   Database: YES
   NAT Gateway: NO
   → Maintaining current configuration

🔨 Building CDK TypeScript...
🚀 Deploying CDK stack...
✅ CDK deployment completed successfully
```

**Output (if no stack exists):**
```
📦 Starting CDK deployment...

⚠️  No existing stack detected
   → Using minimal configuration (no database, no NAT)
   → Use 'deploy-init' to set initial configuration

🔨 Building CDK TypeScript...
🚀 Deploying CDK stack...
✅ CDK deployment completed successfully
```

## Error Handling

### Trying to Remove Database with deploy-init

```bash
# Stack currently has database
./tools.sh aws deploy-init
```

**Output:**
```
⚠️  WARNING: Stack already exists!
   Current configuration:
     Database: YES
     NAT Gateway: NO

   New configuration:
     Database: NO
     NAT Gateway: NO

❌ ERROR: This would DELETE your database!
   Use 'tear-down' first if you want to remove the database.
```

### Using Old Flags on deploy

```bash
./tools.sh aws deploy --with-postgres
```

**Output:**
```
ERROR: Unknown option '--with-postgres'

Use 'deploy-init' to change infrastructure configuration:
  ./tools.sh aws deploy-init --with-postgres
```

## Migration Guide

### For Existing Deployments

If you already have infrastructure deployed:

1. **Check your current configuration:**
   ```bash
   ./tools.sh aws status
   ```

2. **For routine updates, use the new `deploy` command:**
   ```bash
   # This will maintain your current configuration automatically
   ./tools.sh aws deploy
   ```

3. **To add infrastructure (e.g., add database), use `deploy-init`:**
   ```bash
   ./tools.sh aws deploy-init --with-postgres
   ```

### Command Mapping

| Old Command | New Command |
|-------------|-------------|
| `deploy-full --with-postgres` | `deploy-init --with-postgres` |
| `deploy-full` | `deploy-init` |
| `deploy --with-postgres` | `deploy` (detects postgres automatically) |
| `deploy` | `deploy` (safe - maintains current state) |

## Benefits

✅ **Safer Deployments**
- Can't accidentally delete database by forgetting flags
- AWS is the source of truth

✅ **Clearer Intent**
- `deploy-init` = "I want this configuration"
- `deploy` = "Maintain what exists"

✅ **Team-Friendly**
- Works across machines without local state files
- New team members can safely run `deploy`

✅ **Explicit Changes**
- Infrastructure scope changes require using `deploy-init`
- Prevents accidental modifications

## Testing Plan

1. **Test deploy-init on fresh account:**
   - Minimal config
   - With postgres
   - With postgres + NAT

2. **Test deploy maintains state:**
   - After minimal deployment
   - After postgres deployment
   - After full deployment

3. **Test error cases:**
   - deploy-init trying to remove database
   - deploy with no existing stack
   - Invalid AWS credentials

4. **Test migration:**
   - Run on existing deployment with database
   - Verify configuration is maintained

## Files to Modify

### Core Implementation
- `Sources/SwiftDeploy/Services/AWSCLIService.swift` - Add `describeStackResources()`
- `Sources/SwiftDeploy/DeploymentService.swift` - Add `queryDeployedState()`, rename `deployFull()`, update `deploy()`
- `Sources/SwiftDeployCLI/AWSCommand.swift` - Rename command, remove flags

### Documentation
- `CLAUDE.md` - Update all deploy examples
- `README.md` - Update deployment instructions
- `cdk/README.md` - Update CDK deployment docs
- `docs/deploy-command-refactor-plan.md` - This file

### Testing
- Manual testing required
- Consider adding integration tests

## Timeline Estimate

- Step 1 (CloudFormation query): 15-20 minutes
- Step 2 (State detection): 10-15 minutes
- Step 3 (Update deploy): 15-20 minutes
- Step 4 (Rename deployFull): 10 minutes
- Step 5 (Update CLI): 20-25 minutes
- Step 6 (Documentation): 30 minutes
- Testing: 30 minutes

**Total: ~2-2.5 hours**
