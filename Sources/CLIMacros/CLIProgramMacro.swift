import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct CLIProgramMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.message("@CLIProgramMacro can only be applied to structs")
        }

        let structName = structDecl.name.text

        // Extract explicit name from macro arguments if provided
        let programName = extractExplicitName(from: node) ?? toKebabCase(structName)

        let extensionDecl = try ExtensionDeclSyntax("extension \(type): CLIProgram") {
            """
            public static var programName: String { \(literal: programName) }
            """
        }

        return [extensionDecl]
    }

    private static func extractExplicitName(from node: AttributeSyntax) -> String? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let firstArg = arguments.first,
              let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
              let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) else {
            return nil
        }
        return segment.content.text
    }
}

enum MacroError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

/// Convert PascalCase/camelCase to kebab-case
func toKebabCase(_ string: String) -> String {
    var result = ""
    for (index, char) in string.enumerated() {
        if char.isUppercase {
            if index > 0 {
                result.append("-")
            }
            result.append(char.lowercased())
        } else {
            result.append(char)
        }
    }
    return result
}
