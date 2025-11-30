/// Protocol for CLI commands that can be executed
public protocol CLICommand: Sendable {
    /// The parent program type (e.g., Git, Docker)
    associatedtype Program: CLIProgram

    /// The command path as an array of subcommand names (e.g., ["cloudformation", "describe-stacks"])
    /// For simple commands, this is a single-element array (e.g., ["commit"])
    /// For nested commands, this includes all levels (e.g., ["cloudformation", "describe-stacks"])
    static var commandPath: [String] { get }

    /// The argument components for this command
    var arguments: [CLIArgument] { get }
}

// MARK: - Default Implementations

extension CLICommand {
    /// The arguments to pass after the program name (includes subcommand and all flags/options)
    public var commandArguments: [String] {
        var result: [String] = []
        // Add command path components (split any that contain spaces for backwards compatibility)
        for pathComponent in Self.commandPath {
            if pathComponent.contains(" ") {
                result.append(contentsOf: pathComponent.split(separator: " ").map(String.init))
            } else {
                result.append(pathComponent)
            }
        }
        // Add all arguments
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
