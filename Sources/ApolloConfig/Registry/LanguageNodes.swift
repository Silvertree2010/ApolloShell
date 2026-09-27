enum LanguageNodes {
    private static let structural: Set<NodeContext> = [.surfaceBody, .elementBody, .actions, .menu, .commandCenterItems]

    static let all: [NodeSchema] = [
        NodeSchema(
            name: "include",
            category: .language,
            arguments: [ArgumentSchema(name: "path", type: .path, allowsExpression: false, doc: "Path relative to the including file, or builtin:/pkg:.")],
            properties: [PropertySchema(name: "optional", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "A missing file is not an error.")],
            contexts: [.topLevel, .surfaceBody, .elementBody],
            doc: "Includes the top-level nodes of another file at this point.",
            example: "include \"sidebar-modules.kdl\""
        ),
        NodeSchema(
            name: "let",
            category: .language,
            arguments: [],
            properties: [],
            contexts: [.topLevel, .surfaceBody, .elementBody],
            doc: "Declares one or more constants evaluated at load time.",
            example: "let gap=8 radius=12"
        ),
        NodeSchema(
            name: "filter",
            category: .language,
            arguments: [
                ArgumentSchema(name: "name", type: .identifier, allowsExpression: false, doc: "Name used after | in expressions."),
                ArgumentSchema(name: "body", type: .string, allowsExpression: false, doc: "One {…} expression over value and the arguments."),
            ],
            properties: [PropertySchema(name: "args", type: .string, defaultValue: .null, allowsExpression: false, doc: "Names of extra arguments, separated by spaces.")],
            contexts: [.topLevel],
            doc: "Declares a filter made of an expression; value is the piped input.",
            example: "filter \"fahrenheit\" \"{value * 9 / 5 + 32}\""
        ),
        NodeSchema(
            name: "var",
            category: .language,
            arguments: [
                ArgumentSchema(name: "name", type: .identifier, allowsExpression: false, doc: "Name of the state."),
                ArgumentSchema(name: "default", type: .value, required: false, doc: "Default value."),
            ],
            properties: [
                PropertySchema(name: "persist", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "Stores the value in the config's state file."),
                PropertySchema(name: "type", type: .enumeration(["string", "number", "bool", "list", "record", "any"]), defaultValue: .null, allowsExpression: false, doc: "Type of the value, default from the default value."),
                PropertySchema(name: "from", type: .value, defaultValue: .null, doc: "Makes the var derived, not settable."),
            ],
            contexts: [.topLevel],
            doc: "Declares runtime state, optionally persisted.",
            example: "var launcher-query \"\""
        ),
        NodeSchema(
            name: "define",
            category: .language,
            arguments: [ArgumentSchema(name: "name", type: .identifier, allowsExpression: false, doc: "Name of the custom component, kebab-case, globally unique.")],
            properties: [PropertySchema(name: "override", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "Replaces a define of the same name from an included file.")],
            childContext: .elementBody,
            contexts: [.topLevel],
            doc: "Describes a reusable component.",
            example: "define \"labeled-icon\" { param \"icon\"; icon \"{icon}\" }"
        ),
        NodeSchema(
            name: "param",
            category: .language,
            arguments: [ArgumentSchema(name: "name", type: .identifier, allowsExpression: false, doc: "Name of the parameter, visible as an expression in the body.")],
            properties: [
                PropertySchema(name: "default", type: .value, defaultValue: .null, doc: "Makes the parameter optional."),
                PropertySchema(name: "type", type: .enumeration(["string", "number", "bool", "list", "record", "any"]), defaultValue: .null, allowsExpression: false, doc: "Type of the parameter, default any."),
            ],
            contexts: [.elementBody],
            doc: "Declares a parameter of a define.",
            example: "param \"icon\""
        ),
        NodeSchema(
            name: "slot",
            category: .language,
            arguments: [ArgumentSchema(name: "name", type: .identifier, required: false, allowsExpression: false, doc: "Name of the named slot, otherwise the unnamed slot.")],
            contexts: [.elementBody],
            doc: "Place where the children of a use are inserted.",
            example: "slot"
        ),
        NodeSchema(
            name: "fill",
            category: .language,
            arguments: [ArgumentSchema(name: "name", type: .identifier, allowsExpression: false, doc: "Name of the slot filled at use.")],
            childContext: .elementBody,
            contexts: [.elementBody],
            doc: "Fills a named slot of a use.",
            example: "fill \"header\" { text \"Title\" }"
        ),
        NodeSchema(
            name: "use",
            category: .language,
            arguments: [ArgumentSchema(name: "name", type: .identifier, doc: "Name of a define, static or as an expression at runtime.")],
            properties: [],
            childContext: .elementBody,
            contexts: [.topLevel, .surfaceBody, .elementBody, .actions, .menu],
            doc: "Inserts a component described with define.",
            example: "use \"labeled-icon\" icon=\"bar-power\""
        ),
        NodeSchema(
            name: "each",
            category: .language,
            arguments: [ArgumentSchema(name: "variable", type: .identifier, allowsExpression: false, doc: "Name of the loop variable.")],
            properties: [
                PropertySchema(name: "in", type: .list, required: true, doc: "Expression that yields a list."),
                PropertySchema(name: "key", type: .value, defaultValue: .null, doc: "Key of an entry, default id or position."),
                PropertySchema(name: "index", type: .identifier, defaultValue: .null, allowsExpression: false, doc: "Name of the index loop variable."),
            ],
            childContext: .elementBody,
            contexts: structural,
            doc: "Creates children for each entry of a list.",
            example: "each app in=\"{apps.running}\" { text \"{app.name}\" }"
        ),
        NodeSchema(
            name: "when",
            category: .language,
            arguments: [ArgumentSchema(name: "condition", type: .bool, doc: "Condition; the body exists only while it is true.")],
            childContext: .elementBody,
            contexts: structural,
            doc: "Creates children while a condition is true.",
            example: "when \"{battery.present}\" { text \"{battery.percent}\" }"
        ),
        NodeSchema(
            name: "else",
            category: .language,
            childContext: .elementBody,
            contexts: structural,
            doc: "Alternative branch of a directly preceding when or feature.",
            example: "else { text \"No battery\" }"
        ),
        NodeSchema(
            name: "switch",
            category: .language,
            arguments: [ArgumentSchema(name: "subject", type: .value, doc: "Expression whose value selects the branch.")],
            childContext: .elementBody,
            contexts: structural,
            doc: "Selects one of several branches by equality.",
            example: "switch \"{var.tab}\" { case \"a\" { text \"A\" } }"
        ),
        NodeSchema(
            name: "case",
            category: .language,
            arguments: [ArgumentSchema(name: "values", type: .value, variadic: true, doc: "One or more values that select this branch.")],
            childContext: .elementBody,
            contexts: structural,
            doc: "Branch of a switch, applies on the first matching value.",
            example: "case \"a\" \"b\" { text \"A or B\" }"
        ),
        NodeSchema(
            name: "default",
            category: .language,
            childContext: .elementBody,
            contexts: structural,
            doc: "Branch of a switch that applies when no case matches.",
            example: "default { text \"Unknown\" }"
        ),
        NodeSchema(
            name: "feature",
            category: .language,
            arguments: [ArgumentSchema(name: "name", type: .identifier, allowsExpression: false, doc: "Name of the required feature.")],
            childContext: .elementBody,
            contexts: [.topLevel, .surfaceBody, .elementBody, .actions, .menu, .commandCenterItems],
            doc: "Limits the body to shells that know this feature.",
            example: "feature \"wm\" { text \"Tiling\" }"
        ),
        NodeSchema(
            name: "disable",
            category: .language,
            properties: [
                PropertySchema(name: "surface", type: .identifier, defaultValue: .null, allowsExpression: false, doc: "Id of a surface to disable."),
                PropertySchema(name: "bind", type: .keyChord, defaultValue: .null, allowsExpression: false, doc: "Key combination to disable."),
                PropertySchema(name: "on", type: .identifier, defaultValue: .null, allowsExpression: false, doc: "Event name whose handlers are disabled."),
            ],
            contexts: [.topLevel],
            doc: "Disables an included surface, a bind or a handler.",
            example: "disable bind=\"alt+space\""
        ),
        NodeSchema(
            name: "require",
            category: .language,
            arguments: [ArgumentSchema(name: "version", type: .string, required: false, allowsExpression: false, doc: "Minimum shell version.")],
            properties: [PropertySchema(name: "feature", type: .identifier, defaultValue: .null, allowsExpression: false, doc: "Name of a required feature.")],
            contexts: [.topLevel],
            doc: "Stops loading cleanly if the shell is too old or a feature is missing.",
            example: "require \"0.2.0\""
        ),
        NodeSchema(
            name: "style",
            category: .language,
            arguments: [ArgumentSchema(name: "path", type: .path, allowsExpression: false, doc: "Path to a stylesheet file.")],
            contexts: [.topLevel],
            doc: "Includes a stylesheet.",
            example: "style \"theme.css\""
        ),
    ]
}
