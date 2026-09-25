enum SettingsFileNodes {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "config",
            category: .providerSettings,
            arguments: [ArgumentSchema(name: "id", type: .identifier, allowsExpression: false, doc: "Id of the active config.")],
            contexts: [.settingsFile],
            doc: "Selects the active config.",
            example: "config \"apolloshell-default\""
        ),
        NodeSchema(
            name: "theme",
            category: .providerSettings,
            arguments: [ArgumentSchema(name: "id", type: .identifier, required: false, allowsExpression: false, doc: "Theme id or #null for no theme.")],
            contexts: [.settingsFile],
            doc: "Selects the active theme.",
            example: "theme \"Afterglow\""
        ),
        NodeSchema(
            name: "updates",
            category: .providerSettings,
            properties: [
                PropertySchema(name: "auto-check", type: .bool, defaultValue: .bool(true), allowsExpression: false, doc: "Checks for updates automatically."),
                PropertySchema(name: "auto-install", type: .bool, defaultValue: .bool(true), allowsExpression: false, doc: "Installs updates automatically."),
            ],
            contexts: [.settingsFile],
            doc: "Update settings of the shell.",
            example: "updates auto-check=#true auto-install=#true"
        ),
        NodeSchema(
            name: "crash-reports",
            category: .providerSettings,
            arguments: [ArgumentSchema(name: "mode", type: .enumeration(["ask", "always", "never"]), allowsExpression: false, doc: "How crash reports are handled.")],
            contexts: [.settingsFile],
            doc: "Setting for crash reports.",
            example: "crash-reports \"ask\""
        ),
        NodeSchema(
            name: "editor",
            category: .providerSettings,
            arguments: [ArgumentSchema(name: "command", type: .string, allowsExpression: false, doc: "Command to open a file, placeholders {file} {line} {column}.")],
            contexts: [.settingsFile],
            doc: "Editor command for shell.edit.",
            example: "editor \"code -g {file}:{line}:{column}\""
        ),
    ]
}
