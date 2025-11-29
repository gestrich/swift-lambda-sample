/// Marks a struct as a CLI program (executable)
/// The program name is inferred from the struct name (lowercased, kebab-cased)
/// or can be explicitly provided.
///
/// Example:
/// ```swift
/// @CLIProgram
/// struct Git {
///     // commands go here
/// }
/// ```
@attached(extension, conformances: CLIProgram, names: named(programName))
public macro CLIProgram(_ name: String? = nil) = #externalMacro(module: "CLIMacros", type: "CLIProgramMacro")

/// Marks a struct as a CLI command (subcommand)
/// Must be nested inside a @CLIProgram struct.
/// The command name is inferred from the struct name (lowercased, kebab-cased)
/// or can be explicitly provided.
///
/// Example:
/// ```swift
/// @CLIProgram
/// struct Git {
///     @CLICommand
///     struct Merge {
///         @Flag var noFastForward: Bool = false
///         @Positional var branch: String
///     }
/// }
/// ```
@attached(extension, conformances: CLICommand, names: named(commandName), named(arguments), named(Program))
@attached(member, names: named(init))
public macro CLICommand(_ name: String? = nil) = #externalMacro(module: "CLIMacros", type: "CLICommandMacro")

/// Marks a property as a boolean flag
///
/// - No arguments: infers `--kebab-case` from property name
/// - One argument: uses that exact string (e.g., "-f" or "--force")
/// - Two arguments: uses both forms (e.g., "--force", "-f")
///
/// Example:
/// ```swift
/// @Flag var force: Bool = false                    // --force (inferred)
/// @Flag("-f") var force: Bool = false              // -f only
/// @Flag("--force", "-f") var force: Bool = false   // --force and -f
/// @Flag("-version") var version: Bool = false      // -version (java style)
/// ```
@attached(peer)
public macro Flag(_ names: String...) = #externalMacro(module: "CLIMacros", type: "FlagMacro")

/// Marks a property as an option with a value
///
/// - No arguments: infers `--kebab-case` from property name
/// - One argument: uses that exact string (e.g., "-m" or "--message")
/// - Two arguments: uses both forms (e.g., "--message", "-m")
///
/// Example:
/// ```swift
/// @Option var output: String?                        // --output (inferred)
/// @Option("-o") var output: String?                  // -o only
/// @Option("--output", "-o") var output: String?      // --output and -o
/// @Option("-m") var message: String?                 // -m only
/// ```
@attached(peer)
public macro Option(_ names: String...) = #externalMacro(module: "CLIMacros", type: "OptionMacro")

/// Marks a property as a positional argument
/// Positionals are ordered by declaration order
///
/// Example:
/// ```swift
/// @Positional var source: String       // first positional
/// @Positional var destination: String  // second positional
/// ```
@attached(peer)
public macro Positional() = #externalMacro(module: "CLIMacros", type: "PositionalMacro")
