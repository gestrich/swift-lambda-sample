/// Protocol for CLI commands that can be executed
public protocol CLICommand: Sendable {
    /// The parent program type (e.g., Git, Docker)
    associatedtype Program: CLIProgram

    /// The subcommand name (e.g., "merge", "commit")
    static var commandName: String { get }

    /// The argument components for this command
    var arguments: [CLIArgument] { get }
}

// MARK: - Default Implementations

extension CLICommand {
    /// The arguments to pass after the program name (includes subcommand and all flags/options)
    public var commandArguments: [String] {
        var result: [String] = []
        // Only add command name if it's not empty (for programs without subcommands like ls)
        if !Self.commandName.isEmpty {
            result.append(Self.commandName)
        }
        for arg in arguments {
            result.append(contentsOf: arg.components)
        }
        return result
    }

    /// Build the full command line as an array of strings
    public var commandLine: [String] {
        [Program.programName] + commandArguments
    }

    /// Build the full command line as a single string
    public var commandString: String {
        commandLine.map { component in
            if component.contains(" ") {
                return "\"\(component)\""
            }
            return component
        }.joined(separator: " ")
    }
}
