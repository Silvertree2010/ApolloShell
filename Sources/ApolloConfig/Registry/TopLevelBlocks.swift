enum TopLevelBlocks {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "bind",
            category: .topLevelBlock,
            arguments: [ArgumentSchema(name: "chord", type: .keyChord, doc: "Key combination, may be an expression.")],
            properties: [
                PropertySchema(name: "id", type: .identifier, defaultValue: .null, doc: "Id for disable, override and conflict reports, default the combination."),
                PropertySchema(name: "repeat", type: .bool, defaultValue: .bool(false), doc: "Fires while the combination is held."),
                PropertySchema(name: "when", type: .bool, defaultValue: .null, doc: "The bind is active only while the expression is true."),
                PropertySchema(name: "override", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "Allows a second statically identical combination."),
            ],
            childContext: .actions,
            contexts: [.topLevel],
            doc: "Registers a global keyboard shortcut.",
            example: "bind \"alt+space\" { toggle \"launcher\" }"
        ),
        NodeSchema(
            name: "on",
            category: .topLevelBlock,
            arguments: [ArgumentSchema(name: "event", type: .identifier, allowsExpression: false, doc: "Name of the event.")],
            properties: [PropertySchema(name: "when", type: .bool, defaultValue: .null, doc: "Filters when the handler runs; every when of an event is checked before the first handler runs, so two handlers can form a toggle.")],
            childContext: .actions,
            contexts: [.topLevel],
            doc: "Reacts to an event of the shell or a provider. Several on for the same event run in file order.",
            example: "on \"audio.volume-changed\" { osd.show \"volume\" }"
        ),
        NodeSchema(
            name: "poll",
            category: .topLevelBlock,
            feature: "script-sources",
            arguments: [ArgumentSchema(name: "name", type: .identifier, allowsExpression: false, doc: "Name of the source under poll.<name>.")],
            properties: [
                PropertySchema(name: "command", type: .string, required: true, allowsExpression: false, doc: "Command, run via /bin/sh -c.", stability: .stable, feature: "script-sources"),
                PropertySchema(name: "interval", type: .duration, defaultValue: .string("5s"), allowsExpression: false, doc: "Interval between two runs.", feature: "script-sources"),
                PropertySchema(name: "format", type: .enumeration(["text", "json", "lines"]), defaultValue: .string("text"), allowsExpression: false, doc: "How the output is read.", feature: "script-sources"),
                PropertySchema(name: "initial", type: .value, defaultValue: .null, doc: "Value until the first result.", feature: "script-sources"),
                PropertySchema(name: "when", type: .bool, defaultValue: .null, doc: "The source runs only while the expression is true.", feature: "script-sources"),
                PropertySchema(name: "timeout", type: .duration, defaultValue: .string("10s"), allowsExpression: false, doc: "The process is terminated after this.", feature: "script-sources"),
            ],
            contexts: [.topLevel],
            doc: "Repeatedly reads the output of a command as a data source.",
            example: "poll \"vpn\" command=\"scutil --nc status Mullvad | head -1\""
        ),
        NodeSchema(
            name: "listen",
            category: .topLevelBlock,
            feature: "script-sources",
            arguments: [ArgumentSchema(name: "name", type: .identifier, allowsExpression: false, doc: "Name of the source under listen.<name>.")],
            properties: [
                PropertySchema(name: "command", type: .string, required: true, allowsExpression: false, doc: "Command whose output is read line by line.", feature: "script-sources"),
                PropertySchema(name: "format", type: .enumeration(["text", "json", "lines"]), defaultValue: .string("text"), allowsExpression: false, doc: "How each line is read.", feature: "script-sources"),
                PropertySchema(name: "initial", type: .value, defaultValue: .null, doc: "Value until the first result.", feature: "script-sources"),
                PropertySchema(name: "when", type: .bool, defaultValue: .null, doc: "The source runs only while the expression is true.", feature: "script-sources"),
            ],
            contexts: [.topLevel],
            doc: "Reads a long-running data source from a process.",
            example: "listen \"watch-space\" command=\"~/bin/watch-space.sh\" format=\"json\""
        ),
        NodeSchema(
            name: "wm",
            category: .topLevelBlock,
            feature: "wm",
            properties: [PropertySchema(name: "enabled", type: .bool, defaultValue: .bool(false), doc: "Turns the window manager on.")],
            childContext: .wmBlock,
            contexts: [.topLevel],
            doc: "Describes the tiling window manager.",
            example: "wm enabled=#true { layout \"dwindle\" }"
        ),
        NodeSchema(
            name: "command-center",
            category: .topLevelBlock,
            properties: [PropertySchema(name: "visible", type: .bool, defaultValue: .bool(true), doc: "Hides the command center icon.")],
            childContext: .commandCenterItems,
            contexts: [.topLevel],
            doc: "Customizes the items of the native status menu.",
            example: "command-center { builtin \"reload-config\" }"
        ),
        NodeSchema(
            name: "marketplace",
            category: .topLevelBlock,
            properties: [PropertySchema(name: "enabled", type: .bool, defaultValue: .bool(true), allowsExpression: false, doc: "Turns the Marketplace on or off.")],
            contexts: [.topLevel],
            doc: "Turns the built-in Marketplace on or off.",
            example: "marketplace enabled=#false"
        ),
    ]
}
