import Foundation

/// kill CLI program for sending signals to processes
/// Usage: kill [-signal] PID...
///
/// The signal is specified in a special format: -9, -TERM, -KILL, etc.
/// This is handled specially because kill's syntax differs from typical --option value format.
public struct Kill: CLIProgram, CLICommand {
    public static var programName: String { "kill" }
    public typealias Program = Kill
    public static var commandName: String { "" }

    /// Signal to send (e.g., "9", "TERM", "KILL"). Defaults to TERM if not specified.
    public var signal: String?

    /// Process ID to send signal to
    public var pid: String

    public init(signal: String? = nil, pid: String) {
        self.signal = signal
        self.pid = pid
    }

    public var arguments: [CLIArgument] {
        var args: [CLIArgument] = []
        // Signal is formatted as -SIGNAL (e.g., -9, -TERM) - combined into single flag
        if let signal = signal {
            args.append(.flag(CLIFlag("-\(signal)")))
        }
        args.append(.positional(CLIPositional(pid)))
        return args
    }
}
