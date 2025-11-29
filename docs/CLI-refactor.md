# CLI Refactor

## CLI Semantics

```
git merge --no-ff -m "message" feature-branch
│   │      │       │  │        │
│   │      │       │  │        └── positional argument
│   │      │       │  └── option value
│   │      │       └── option (takes a value)
│   │      └── flag (boolean, no value)
│   └── subcommand
└── program
```

## Core Types

### CLIProgram
- Represents an executable (git, docker, swift)
- Contains nested CLICommand types

### CLICommand
- Represents a subcommand with its arguments
- Uses macros for declarative definition

### CLIController
- Executes CLIProgram instances
- Can spawn child controllers for streaming context

## Macro-Based API

### Name Inference

Program and command names are inferred from the struct name (lowercased, kebab-cased):

| Declaration | Inferred Name |
|-------------|---------------|
| `@CLIProgram struct Git` | `git` |
| `@CLICommand struct Merge` | `merge` |
| `@CLICommand struct UpdateIndex` | `update-index` |

Override when the name doesn't match:

```swift
@CLIProgram("git")           // explicit
@CLIProgram struct Git       // inferred: "git"

@CLICommand("update-index")  // explicit
@CLICommand struct UpdateIndex  // inferred: "update-index"
```

### Flags and Options

Long form is inferred from property name (kebab-cased by default). Use `shortFlag:` to add a short form.

```swift
// @Flag - long form inferred from property name
@Flag var force: Bool = false                      // --force
@Flag var noFastForward: Bool = false              // --no-fast-forward
@Flag(shortFlag: "-f") var force: Bool = false     // --force and -f
@Flag(shortFlag: "-a") var all: Bool = false       // --all and -a

// @ShortFlag - short form only, no long form
@ShortFlag("-v") var verbose: Bool = false         // -v only
@ShortFlag("-a") var all: Bool = false             // -a only

// @Option - long form inferred from property name
@Option var output: String?                        // --output
@Option var message: String?                       // --message
@Option(shortFlag: "-o") var output: String?       // --output and -o
@Option(shortFlag: "-m") var message: String?      // --message and -m

// @ShortOption - short form only, no long form
@ShortOption("-m") var message: String?            // -m only
@ShortOption("-o") var output: String?             // -o only
```

### Verbatim Names

By default, property names are converted to kebab-case. Use `verbatim: true` to use the exact property name:

```swift
@Flag var noFastForward: Bool = false                    // --no-fast-forward
@Flag(verbatim: true) var noFastForward: Bool = false    // --noFastForward

@Option var outputFile: String?                          // --output-file
@Option(verbatim: true) var outputFile: String?          // --outputFile
```

### Definition

```swift
@CLIProgram
struct Git {
    @CLICommand
    struct Merge {
        @Flag var noFastForward: Bool = false          // --no-fast-forward
        @ShortOption("-m") var message: String?        // -m only
        @Positional var branch: String
    }

    @CLICommand
    struct Clone {
        @Positional var repository: String
        @Positional var directory: String?  // optional = can omit
    }

    @CLICommand
    struct Commit {
        @ShortFlag("-a") var all: Bool = false         // -a only
        @Flag var amend: Bool = false                  // --amend
        @ShortOption("-m") var message: String         // -m only (required)
    }
}

@CLIProgram
struct Docker {
    @CLICommand
    struct Run {
        @ShortFlag("-d") var detached: Bool = false    // -d only
        @Flag var rm: Bool = false                     // --rm
        @ShortOption("-p") var port: String?           // -p only
        @ShortOption("-v") var volume: String?         // -v only
        @Positional var image: String
    }
}
```

### Positional Ordering

Positionals use declaration order (macro reads top-to-bottom). No explicit indices needed:

```swift
@CLICommand
struct Copy {
    @Flag("-r") var recursive: Bool = false
    @Positional var source: String       // first
    @Positional var destination: String  // second
}
```

### Generated Code

The macro generates `CLICommand` conformance:

```swift
struct Merge: CLICommand {
    var branch: String
    var noFastForward: Bool = false
    var message: String?

    // Generated
    var subcommand: String { "merge" }

    // Generated
    var components: [CLIArgument] {
        var args: [CLIArgument] = []
        if noFastForward { args.append(.flag(Flag("--no-ff"))) }
        if let message { args.append(.option(Option("-m", value: message))) }
        args.append(.positional(Positional(branch)))
        return args
    }
}
```

## Client Usage

### Basic Execution

```swift
let controller = CLIController()

// Simple
let merge = Git.Merge(branch: "feature-branch")
try await controller.run(merge)
// -> git merge feature-branch

// With options
let merge2 = Git.Merge(
    branch: "feature-branch",
    noFastForward: true,
    message: "Merge feature"
)
try await controller.run(merge2)
// -> git merge --no-ff -m "Merge feature" feature-branch

// Docker
let docker = Docker.Run(
    image: "postgres:15",
    detached: true,
    remove: true,
    port: "5432:5432"
)
try await controller.run(docker)
// -> docker run -d --rm -p 5432:5432 postgres:15
```

### Streaming

```swift
for await item in controller.stream(Git.Commit(all: true, message: "Update")) {
    switch item {
    case .command(let id, let cmd):
        print("Running: \(cmd)")
    case .output(let id, let line):
        print(line)
    }
}
```

## Flows

Define sequences of commands to run in succession:

```swift
let deployFlow = Flow {
    Git.Commit(all: true, message: "Deploy")
    Git.Push(branch: "main")
    Docker.Build(tag: "app:latest")
    Docker.Push(image: "app:latest")
}

for await item in controller.stream(deployFlow) {
    // streams all commands in sequence
}
```

## Interactive Flow Runner

Show command details before execution:

```swift
let runner = InteractiveRunner(controller: controller)

// Shows UI for each step:
// > git commit -a -m "Deploy"
//   -a: Stage all modified files
//   -m: Commit message
// [Run] [Skip] [Edit]

try await runner.execute(deployFlow)
```

## Research

- Look at new Swift CLI library for inspiration
