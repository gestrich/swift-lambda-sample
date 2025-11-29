import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct CLIMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        CLICommandMacro.self,
        CLIProgramMacro.self,
        FlagMacro.self,
        OptionMacro.self,
        PositionalMacro.self,
        PrefixOptionMacro.self,
    ]
}
