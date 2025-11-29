import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct CLIMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        CLIProgramMacro.self,
        CLICommandMacro.self,
        FlagMacro.self,
        ShortFlagMacro.self,
        OptionMacro.self,
        ShortOptionMacro.self,
        PositionalMacro.self,
    ]
}
