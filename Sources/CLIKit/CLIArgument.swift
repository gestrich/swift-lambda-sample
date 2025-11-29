/// Represents a single CLI argument component
public enum CLIArgument: Equatable, Sendable {
    case flag(CLIFlag)
    case option(CLIOption)
    case positional(CLIPositional)

    /// Convert to command-line string components
    public var components: [String] {
        switch self {
        case .flag(let flag):
            return flag.components
        case .option(let option):
            return option.components
        case .positional(let positional):
            return positional.components
        }
    }
}

/// A boolean flag (e.g., --force, -f)
public struct CLIFlag: Equatable, Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    public var components: [String] {
        [name]
    }
}

/// An option with a value (e.g., --message "text", -m "text")
public struct CLIOption: Equatable, Sendable {
    public let name: String
    public let value: String

    public init(_ name: String, value: String) {
        self.name = name
        self.value = value
    }

    public var components: [String] {
        [name, value]
    }
}

/// A positional argument (e.g., branch name, file path)
public struct CLIPositional: Equatable, Sendable {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var components: [String] {
        [value]
    }
}
