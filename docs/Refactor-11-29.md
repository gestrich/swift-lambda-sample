# CLIKit Nested Command Refactor

## Overview

Refactor CLIKit to support true nested `@CLICommand` structs, eliminating the need for space-separated command names like `@CLICommand("cloudformation describe-stacks")`.

## Current State

### The Problem

The current architecture uses space-separated strings to represent compound commands:

```swift
@CLIProgram
public struct Aws {
    @CLICommand("cloudformation describe-stacks")
    public struct CloudFormationDescribeStacks {
        @Option public var stackName: String
        // ...
    }
}
```

The comment in `CLICommand.swift:20` says:
> Split by spaces to support multi-word commands like "cloudformation describe-stacks"

But "cloudformation describe-stacks" isn't really a "multi-word command" - it's a **service + subcommand** hierarchy that's being flattened into a string.

### Current Architecture

```
CLIProgram (protocol)
  - programName: String        # e.g., "aws"

CLICommand (protocol)
  - commandName: String        # e.g., "cloudformation describe-stacks"
  - arguments: [CLIArgument]
  - Program: CLIProgram        # Parent program type

@CLIProgram macro
  - Conforms struct to CLIProgram
  - If struct has @Flag/@Option/@Positional properties, also conforms to CLICommand

@CLICommand macro
  - Conforms struct to CLICommand
  - Finds parent CLIProgram via lexical context
  - Generates commandName from struct name or explicit string
```

## Proposed State

### Goal

Support true nesting where each level is a `@CLICommand`:

```swift
@CLIProgram
public struct Aws {
    @CLICommand
    public struct CloudFormation {
        @CLICommand
        public struct DescribeStacks {
            @Option public var stackName: String
            @Option public var profile: String
        }

        @CLICommand
        public struct DescribeStackResources {
            @Option public var stackName: String
            @Option public var profile: String
        }
    }

    @CLICommand
    public struct Lambda {
        @CLICommand
        public struct UpdateFunctionCode {
            @Option public var functionName: String
            @Option public var zipFile: String
            @Option public var profile: String
        }
    }
}

// Usage:
let cmd = Aws.CloudFormation.DescribeStacks(stackName: "MyStack", profile: "prod")
cmd.commandLine  // ["aws", "cloudformation", "describe-stacks", "--stack-name", "MyStack", "--profile", "prod"]
```

### Key Insight: Programs Are Commands

A program is just a root command. The distinction is artificial:
- `CLIProgram` provides the executable name
- `CLICommand` provides the subcommand name and arguments

We can unify these concepts:
- A command without a parent is a "root command" (program)
- A command with a parent inherits context from the parent chain

## Implementation Plan

### Phase 1: Update CLICommand Macro

**File: `Sources/CLIMacros/CLICommandMacro.swift`**

1. **Collect full parent chain** (not just immediate parent):

```swift
private static func extractCommandChain(from context: some MacroExpansionContext) -> [CommandInfo] {
    var chain: [CommandInfo] = []

    for lexicalContext in context.lexicalContext {
        if let structDecl = lexicalContext.as(StructDeclSyntax.self) {
            // Check if this struct has @CLICommand or @CLIProgram attribute
            let hasCommandAttr = structDecl.attributes.contains { attr in
                guard let attrSyntax = attr.as(AttributeSyntax.self),
                      let identifier = attrSyntax.attributeName.as(IdentifierTypeSyntax.self) else {
                    return false
                }
                return identifier.name.text == "CLICommand" || identifier.name.text == "CLIProgram"
            }

            if hasCommandAttr {
                let explicitName = extractExplicitNameFromStruct(structDecl)
                chain.append(CommandInfo(
                    typeName: structDecl.name.text,
                    commandName: explicitName ?? toKebabCase(structDecl.name.text),
                    isProgram: /* check if @CLIProgram */
                ))
            }
        }
    }

    return chain.reversed()  // Root first
}
```

2. **Build commandName from chain**:

```swift
// For Aws.CloudFormation.DescribeStacks:
// chain = [Aws (program), CloudFormation (command), DescribeStacks (command)]
// commandName = "cloudformation describe-stacks" (skip program, join rest)
```

3. **Find root program type**:

```swift
// Program type is always the first item in the chain (the @CLIProgram)
let programType = chain.first?.typeName ?? "_UnknownProgram"
```

### Phase 2: Handle Intermediate Commands (Namespaces)

Commands like `CloudFormation` that have no flags/options but contain subcommands need special handling:

```swift
@CLICommand
public struct CloudFormation {
    // No properties - this is a namespace

    @CLICommand
    public struct DescribeStacks { ... }
}
```

The macro should:
- Still conform to `CLICommand` protocol
- Generate empty `arguments` array
- Generate appropriate `commandName`
- **Not generate an initializer** (no properties to initialize)

### Phase 3: Update CLICommand Protocol (Optional)

Consider whether `commandName` should remain a computed string or become structured:

```swift
// Option A: Keep as string (simpler, current approach)
static var commandName: String { "cloudformation describe-stacks" }

// Option B: Make it an array (more explicit)
static var commandPath: [String] { ["cloudformation", "describe-stacks"] }
```

Recommendation: Keep as string for backward compatibility. The space-splitting in `commandArguments` already handles this.

### Phase 4: Refactor Aws CLI

**File: `Sources/SwiftDeploy/CLI/Aws.swift`**

Before:
```swift
@CLIProgram
public struct Aws {
    @CLICommand("cloudformation describe-stacks")
    public struct CloudFormationDescribeStacks {
        @Option public var stackName: String
        @Option public var profile: String
        // ...
    }

    @CLICommand("lambda update-function-code")
    public struct LambdaUpdateFunctionCode {
        @Option public var functionName: String
        // ...
    }
}
```

After:
```swift
@CLIProgram
public struct Aws {
    @CLICommand
    public struct CloudFormation {
        @CLICommand
        public struct DescribeStacks {
            @Option public var stackName: String
            @Option public var profile: String
            // ...
        }

        @CLICommand
        public struct DescribeStackResources {
            @Option public var stackName: String
            @Option public var profile: String
            // ...
        }
    }

    @CLICommand
    public struct Lambda {
        @CLICommand
        public struct UpdateFunctionCode {
            @Option public var functionName: String
            // ...
        }

        @CLICommand
        public struct GetFunction {
            @Option public var functionName: String
            // ...
        }
    }

    @CLICommand
    public struct Logs {
        @CLICommand
        public struct Tail {
            @Positional public var logGroup: String
            @Option public var since: String?
            // ...
        }
    }

    @CLICommand
    public struct S3 {
        @CLICommand
        public struct Ls {
            @Positional public var path: String
            @Option public var profile: String
        }

        @CLICommand
        public struct Cp {
            @Positional public var source: String
            @Positional public var destination: String
            @Option public var profile: String
        }
    }

    @CLICommand
    public struct SecretsManager {
        @CLICommand
        public struct GetSecretValue {
            @Option public var secretId: String
            // ...
        }

        @CLICommand
        public struct ListSecrets {
            @Option public var profile: String
            // ...
        }
    }
}
```

### Phase 5: Update Tests

**File: `Tests/SwiftDeployTests/AWSCLITests.swift`**

Update test references:
```swift
// Before
Aws.CloudFormationDescribeStacks(stackName: "MyStack", profile: "prod")

// After
Aws.CloudFormation.DescribeStacks(stackName: "MyStack", profile: "prod")
```

### Phase 6: Update Usages in Services

Search for all usages of the old flat names and update them:
```bash
grep -r "Aws\." Sources/SwiftDeploy --include="*.swift"
```

## Edge Cases to Handle

### 1. Empty Namespace Commands

Commands that only contain other commands (no flags/options):
```swift
@CLICommand
public struct CloudFormation {
    // No init needed, no arguments property content
}
```

The macro should detect this and:
- Not generate a memberwise init
- Generate `arguments` that returns `[]`

### 2. Explicit Command Names

Still support explicit names for edge cases:
```swift
@CLICommand("s3")  // Override default "s-3" from struct name S3
public struct S3 { ... }
```

### 3. Mixed Depth

Some commands are 2 levels, some are 3:
```swift
@CLIProgram
public struct Gh {
    @CLICommand
    public struct Run {
        @CLICommand
        public struct List { ... }  // gh run list

        @CLICommand
        public struct Watch { ... } // gh run watch
    }

    @CLICommand
    public struct Pr {
        @CLICommand
        public struct Create { ... } // gh pr create
    }
}
```

### 4. Backward Compatibility

The space-separated string approach should continue to work for:
- Existing code that hasn't been migrated
- Simple cases where nesting is overkill

## Files to Modify

1. **`Sources/CLIMacros/CLICommandMacro.swift`** - Main macro changes
2. **`Sources/SwiftDeploy/CLI/Aws.swift`** - Refactor to nested structure
3. **`Sources/SwiftDeploy/CLI/Gh.swift`** - Refactor to nested structure (already uses `@CLICommand("run list")` etc.)
4. **`Tests/SwiftDeployTests/AWSCLITests.swift`** - Update test references
5. **`Tests/SwiftDeployTests/GhCLITests.swift`** - Update if exists
6. **Various service files** - Update usages of CLI commands

## Testing Strategy

1. **Unit tests for macro output** - Verify generated code is correct
2. **Integration tests** - Verify `commandLine` produces correct arrays
3. **Manual testing** - Run actual CLI commands to verify they work

## Benefits

1. **Better IDE discoverability** - Type `Aws.Cloud` and see all CloudFormation commands
2. **Clearer structure** - Code mirrors CLI hierarchy
3. **Shared options potential** - Could add common options at namespace level (future)
4. **Conceptual clarity** - No more "multi-word commands" confusion

## Risks

1. **Breaking changes** - All usages need updating
2. **Macro complexity** - Parent chain walking is more complex
3. **Compile time** - More nested types might slow compilation slightly

## Migration Approach

**Clean migration - no legacy typealiases.** Update all usages in one pass rather than maintaining backward-compatible aliases like:

```swift
// DON'T do this:
typealias CloudFormationDescribeStacks = CloudFormation.DescribeStacks
```

This keeps the codebase clean and forces a complete migration.

## Open Questions

1. Should `CLIProgram` be deprecated in favor of `@CLICommand(root: true)` or similar?
2. Should namespace commands (without properties) require an explicit marker?
3. How to handle shared options at the namespace level (e.g., `--profile` on all AWS commands)?
