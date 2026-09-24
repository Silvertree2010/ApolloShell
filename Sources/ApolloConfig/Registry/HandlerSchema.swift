enum HandlerSchema {
    static let common: [PropertySchema] = [
        PropertySchema(name: "debounce", type: .duration, defaultValue: .null, allowsExpression: false, doc: "löst erst aus, wenn so lange nichts Neues kam."),
        PropertySchema(name: "throttle", type: .duration, defaultValue: .null, allowsExpression: false, doc: "löst höchstens einmal je Dauer aus."),
    ]

    static func synthesize(_ name: String) -> NodeSchema {
        var arguments: [ArgumentSchema] = []
        var properties = common
        switch name {
        case "key":
            arguments = [ArgumentSchema(name: "chord", type: .keyChord, allowsExpression: false, doc: "Tastenkombination.")]
        case "on-drop":
            properties.append(PropertySchema(name: "accept", type: .enumeration(["files", "apps", "text"]), required: true, allowsExpression: false, doc: "welche Art abgelegter Inhalte."))
        case "on-scroll":
            properties.append(contentsOf: [
                PropertySchema(name: "step", type: .number, defaultValue: .null, doc: "Scrollweg, bis ausgelöst wird."),
                PropertySchema(name: "cooldown", type: .duration, defaultValue: .null, allowsExpression: false, doc: "Pause nach dem Auslösen."),
            ])
        case "on-long-press":
            properties.append(PropertySchema(name: "delay", type: .duration, defaultValue: .string("500ms"), allowsExpression: false, doc: "Verzögerung bis zum Auslösen."))
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
