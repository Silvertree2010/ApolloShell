enum HandlerSchema {
    static let common: [PropertySchema] = [
        PropertySchema(name: "debounce", type: .duration, defaultValue: .null, allowsExpression: false, doc: "Fires only after nothing new arrived for this long."),
        PropertySchema(name: "throttle", type: .duration, defaultValue: .null, allowsExpression: false, doc: "Fires at most once per duration."),
    ]

    static func synthesize(_ name: String) -> NodeSchema {
        var arguments: [ArgumentSchema] = []
        var properties = common
        switch name {
        case "key":
            arguments = [ArgumentSchema(name: "chord", type: .keyChord, allowsExpression: false, doc: "Key combination.")]
        case "on-drop":
            properties.append(PropertySchema(name: "accept", type: .enumeration(["files", "apps", "text"]), required: true, allowsExpression: false, doc: "Which kind of dropped content."))
        case "on-scroll":
            properties.append(contentsOf: [
                PropertySchema(name: "step", type: .number, defaultValue: .null, doc: "Scroll distance until it fires."),
                PropertySchema(name: "cooldown", type: .duration, defaultValue: .null, allowsExpression: false, doc: "Pause after firing."),
            ])
        case "on-long-press":
            properties.append(PropertySchema(name: "delay", type: .duration, defaultValue: .string("500ms"), allowsExpression: false, doc: "Delay until it fires."))
        default:
            break
        }
        return NodeSchema(
            name: name,
            category: .action,
            arguments: arguments,
            properties: properties,
            childContext: .actions,
            contexts: [.surfaceBody, .elementBody],
            doc: "Handler.",
            example: name
        )
    }
}
