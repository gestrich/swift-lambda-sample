import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct CLICommandMacro: ExtensionMacro, MemberMacro {

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.message("@CLICommandMacro can only be applied to structs")
        }

        let structName = structDecl.name.text

        // Extract explicit name from macro arguments if provided
        let commandName = extractExplicitName(from: node) ?? toKebabCase(structName)

        // Extract program type from lexical context (parent struct)
        let programType = extractParentType(from: context)

        // Parse properties with CLI attributes
        let properties = parseProperties(from: structDecl)

        // Generate arguments computed property
        let argumentsCode = generateArgumentsCode(properties: properties)

        let extensionDecl = try ExtensionDeclSyntax("extension \(type): CLICommand") {
            """
            public typealias Program = \(raw: programType)

            public static var commandName: String { \(literal: commandName) }

            public var arguments: [CLIArgument] {
                var args: [CLIArgument] = []
                \(raw: argumentsCode)
                return args
            }
            """
        }

        return [extensionDecl]
    }

    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.message("@CLICommandMacro can only be applied to structs")
        }

        // Parse properties to generate memberwise init
        let properties = parseProperties(from: structDecl)

        // Generate initializer
        let initDecl = generateInitializer(properties: properties)

        return [DeclSyntax(initDecl)]
    }

    // MARK: - Helpers

    private static func extractExplicitName(from node: AttributeSyntax) -> String? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }

        // Look for labeled "name:" argument or unlabeled first string argument
        for arg in arguments {
            if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                return segment.content.text
            }
        }
        return nil
    }

    private static func extractParentType(from context: some MacroExpansionContext) -> String {
        // Walk through lexical context to find parent struct
        for lexicalContext in context.lexicalContext {
            if let structDecl = lexicalContext.as(StructDeclSyntax.self) {
                return structDecl.name.text
            }
        }
        return "_UnknownProgram"
    }
}

// MARK: - Property Parsing

struct ParsedProperty {
    let name: String
    let type: String
    let isOptional: Bool
    let hasDefault: Bool
    let defaultValue: String?
    let attribute: PropertyAttribute
}

enum PropertyAttribute {
    /// Flag with explicit names (can be empty for inferred, one name, or two names)
    case flag(names: [String])
    /// Option with explicit names (can be empty for inferred, one name, or two names)
    case option(names: [String])
    /// Prefix option where prefix and value are joined (e.g., -9 for kill)
    case prefixOption(prefix: String)
    case positional
    case none
}

func parseProperties(from structDecl: StructDeclSyntax) -> [ParsedProperty] {
    var properties: [ParsedProperty] = []

    for member in structDecl.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
            continue
        }

        let name = pattern.identifier.text

        // Get type info
        var typeString = "String"
        var isOptional = false

        if let typeAnnotation = binding.typeAnnotation {
            let type = typeAnnotation.type
            if let optionalType = type.as(OptionalTypeSyntax.self) {
                isOptional = true
                typeString = optionalType.wrappedType.description.trimmingCharacters(in: .whitespaces)
            } else {
                typeString = type.description.trimmingCharacters(in: .whitespaces)
            }
        }

        // Check for default value
        let hasDefault = binding.initializer != nil
        var defaultValue: String? = nil
        if let initializer = binding.initializer {
            defaultValue = initializer.value.description.trimmingCharacters(in: .whitespaces)
        }

        // Parse attribute
        let attribute = parseAttribute(from: varDecl)

        properties.append(ParsedProperty(
            name: name,
            type: typeString,
            isOptional: isOptional,
            hasDefault: hasDefault,
            defaultValue: defaultValue,
            attribute: attribute
        ))
    }

    return properties
}

func parseAttribute(from varDecl: VariableDeclSyntax) -> PropertyAttribute {
    for attr in varDecl.attributes {
        guard let attribute = attr.as(AttributeSyntax.self),
              let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self) else {
            continue
        }

        let attrName = identifier.name.text

        switch attrName {
        case "Flag":
            let names = parseVariadicStringArgs(from: attribute)
            return .flag(names: names)

        case "Option":
            let names = parseVariadicStringArgs(from: attribute)
            return .option(names: names)

        case "PrefixOption":
            let args = parseVariadicStringArgs(from: attribute)
            let prefix = args.first ?? "-"
            return .prefixOption(prefix: prefix)

        case "Positional":
            return .positional

        default:
            continue
        }
    }

    return .none
}

/// Parse variadic string arguments from an attribute
/// Handles: @Flag, @Flag("-f"), @Flag("--force", "-f")
func parseVariadicStringArgs(from attribute: AttributeSyntax) -> [String] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return []
    }

    var names: [String] = []

    for arg in arguments {
        if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
            names.append(segment.content.text)
        }
    }

    return names
}

// MARK: - Code Generation

func generateArgumentsCode(properties: [ParsedProperty]) -> String {
    var lines: [String] = []

    // First add flags and options, then positionals
    for prop in properties {
        switch prop.attribute {
        case .flag(let names):
            // Determine the flag name to use:
            // - Empty names: infer from property name (--kebab-case)
            // - One name: use that exact name
            // - Two names: use the first (long form)
            let flagName: String
            if names.isEmpty {
                flagName = "--\(toKebabCase(prop.name))"
            } else {
                flagName = names[0]
            }
            lines.append("if self.\(prop.name) { args.append(.flag(CLIFlag(\"\(flagName)\"))) }")

        case .option(let names):
            // Determine the option name to use:
            // - Empty names: infer from property name (--kebab-case)
            // - One name: use that exact name
            // - Two names: use the first (long form)
            let optionName: String
            if names.isEmpty {
                optionName = "--\(toKebabCase(prop.name))"
            } else {
                optionName = names[0]
            }
            if prop.isOptional {
                lines.append("if let value = self.\(prop.name) { args.append(.option(CLIOption(\"\(optionName)\", value: value))) }")
            } else {
                lines.append("args.append(.option(CLIOption(\"\(optionName)\", value: self.\(prop.name))))")
            }

        case .prefixOption(let prefix):
            // Prefix option joins prefix and value (e.g., -9 for kill)
            if prop.isOptional {
                lines.append("if let value = self.\(prop.name) { args.append(.prefixOption(CLIPrefixOption(\"\(prefix)\", value: value))) }")
            } else {
                lines.append("args.append(.prefixOption(CLIPrefixOption(\"\(prefix)\", value: self.\(prop.name))))")
            }

        case .positional:
            if prop.isOptional {
                lines.append("if let value = self.\(prop.name) { args.append(.positional(CLIPositional(value))) }")
            } else {
                lines.append("args.append(.positional(CLIPositional(self.\(prop.name))))")
            }

        case .none:
            continue
        }
    }

    return lines.joined(separator: "\n        ")
}

func generateInitializer(properties: [ParsedProperty]) -> InitializerDeclSyntax {
    // Build parameter list
    var params: [String] = []

    for prop in properties {
        // Skip properties without CLI attributes
        guard case .none = prop.attribute else {
            let paramType = prop.isOptional ? "\(prop.type)?" : prop.type
            if let defaultValue = prop.defaultValue {
                params.append("\(prop.name): \(paramType) = \(defaultValue)")
            } else if prop.isOptional {
                params.append("\(prop.name): \(paramType) = nil")
            } else {
                params.append("\(prop.name): \(paramType)")
            }
            continue
        }
    }

    // Build assignments
    var assignments: [String] = []
    for prop in properties {
        guard case .none = prop.attribute else {
            assignments.append("self.\(prop.name) = \(prop.name)")
            continue
        }
    }

    let paramList = params.joined(separator: ", ")
    let bodyStatements = assignments.joined(separator: "\n        ")

    return try! InitializerDeclSyntax("public init(\(raw: paramList))") {
        "\(raw: bodyStatements)"
    }
}
