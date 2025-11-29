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
/// Long form is inferred from property name (kebab-cased by default)
///
/// Example:
/// ```swift
/// @Flag var force: Bool = false                    // --force
/// @Flag var noFastForward: Bool = false            // --no-fast-forward
/// @Flag(shortFlag: "-f") var force: Bool = false   // --force and -f
/// @Flag(verbatim: true) var noFF: Bool = false     // --noFF (no conversion)
/// ```
@attached(peer)
public macro Flag(shortFlag: String? = nil, verbatim: Bool = false) = #externalMacro(module: "CLIMacros", type: "FlagMacro")

/// Marks a property as a short-form-only flag (no long form)
///
/// Example:
/// ```swift
/// @ShortFlag("-v") var verbose: Bool = false  // -v only
/// @ShortFlag("-a") var all: Bool = false      // -a only
/// ```
@attached(peer)
public macro ShortFlag(_ flag: String) = #externalMacro(module: "CLIMacros", type: "ShortFlagMacro")

/// Marks a property as an option with a value
/// Long form is inferred from property name (kebab-cased by default)
///
/// Example:
/// ```swift
/// @Option var output: String?                      // --output
/// @Option var message: String?                     // --message
/// @Option(shortFlag: "-o") var output: String?     // --output and -o
/// @Option(verbatim: true) var outputFile: String?  // --outputFile (no conversion)
/// ```
@attached(peer)
public macro Option(shortFlag: String? = nil, verbatim: Bool = false) = #externalMacro(module: "CLIMacros", type: "OptionMacro")

/// Marks a property as a short-form-only option (no long form)
///
/// Example:
/// ```swift
/// @ShortOption("-m") var message: String?  // -m only
/// @ShortOption("-o") var output: String?   // -o only
/// ```
@attached(peer)
public macro ShortOption(_ option: String) = #externalMacro(module: "CLIMacros", type: "ShortOptionMacro")

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
