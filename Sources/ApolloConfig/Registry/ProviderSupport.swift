enum ProviderSupport {
    static func field(_ path: String, _ type: ValueType, nullable: Bool = false, update: UpdateKind, doc: String) -> FieldSchema {
        FieldSchema(path: path.split(separator: ".").map(String.init), type: type, nullable: nullable, update: update, doc: doc)
    }

    static func action(_ name: String, _ arguments: [ArgumentSchema] = [], doc: String, waits: Bool = false, startsProgramsOrControlsApps: Bool = false) -> ActionSchema {
        ActionSchema(name: name, arguments: arguments, waits: waits, startsProgramsOrControlsApps: startsProgramsOrControlsApps, doc: doc)
    }

    static func event(_ name: String, _ fields: [FieldSchema] = [], doc: String) -> EventSchema {
        EventSchema(name: name, fields: fields, doc: doc)
    }

    static func arg(_ name: String, _ type: ValueType = .any, required: Bool = true, doc: String) -> ArgumentSchema {
        ArgumentSchema(name: name, type: type, required: required, doc: doc)
    }
}
