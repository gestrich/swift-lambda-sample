import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct CLIMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        CLIProgramMacro.self,
        CLICommandMacro.self,
        FlagMacro.self,
        OptionMacro.self,
        PositionalMacro.self,
    ]
}
