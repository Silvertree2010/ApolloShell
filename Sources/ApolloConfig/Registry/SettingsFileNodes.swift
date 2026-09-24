enum SettingsFileNodes {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "config",
            category: .providerSettings,
            arguments: [ArgumentSchema(name: "id", type: .identifier, allowsExpression: false, doc: "Kennung der aktiven Config.")],
            contexts: [.settingsFile],
            doc: "wählt die aktive Config.",
            example: "config \"apolloshell-default\""
        ),
        NodeSchema(
            name: "theme",
            category: .providerSettings,
            arguments: [ArgumentSchema(name: "id", type: .identifier, required: false, allowsExpression: false, doc: "Theme-Kennung oder #null für kein Theme.")],
            contexts: [.settingsFile],
            doc: "wählt das aktive Theme.",
            example: "theme \"Afterglow\""
        ),
        NodeSchema(
            name: "updates",
            category: .providerSettings,
            properties: [
                PropertySchema(name: "auto-check", type: .bool, defaultValue: .bool(true), allowsExpression: false, doc: "prüft automatisch auf Updates."),
                PropertySchema(name: "auto-install", type: .bool, defaultValue: .bool(true), allowsExpression: false, doc: "installiert Updates automatisch."),
            ],
            contexts: [.settingsFile],
            doc: "Update-Einstellungen der Shell.",
            example: "updates auto-check=#true auto-install=#true"
        ),
        NodeSchema(
            name: "crash-reports",
            category: .providerSettings,
            arguments: [ArgumentSchema(name: "mode", type: .enumeration(["ask", "always", "never"]), allowsExpression: false, doc: "wie mit Absturzberichten verfahren wird.")],
            contexts: [.settingsFile],
            doc: "Einstellung für Absturzberichte.",
            example: "crash-reports \"ask\""
        ),
        NodeSchema(
            name: "editor",
            category: .providerSettings,
            arguments: [ArgumentSchema(name: "command", type: .string, allowsExpression: false, doc: "Befehl zum Öffnen einer Datei, Platzhalter {file} {line} {column}.")],
            contexts: [.settingsFile],
            doc: "Editor-Befehl für shell.edit.",
            example: "editor \"code -g {file}:{line}:{column}\""
        ),
    ]
}
