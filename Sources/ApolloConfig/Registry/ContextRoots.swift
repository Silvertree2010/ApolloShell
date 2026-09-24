enum ContextRoots {
    private typealias S = ProviderSupport

    static let all: [ContextRootSchema] = [
        ContextRootSchema(
            name: "self",
            fields: [
                S.field("hover", .bool, update: .push, doc: "ob der Zeiger über dem Baustein ist."),
                S.field("pressed", .bool, update: .push, doc: "ob der Baustein gerade gedrückt ist."),
                S.field("focused", .bool, update: .push, doc: "ob der Baustein den Fokus hat."),
            ],
            validIn: ["surfaceBody", "elementBody"]
        ),
        ContextRootSchema(
            name: "surface",
            fields: [
                S.field("id", .identifier, update: .once, doc: "Kennung der Oberfläche."),
                S.field("open", .bool, update: .push, doc: "ob die Oberfläche offen ist."),
                S.field("opening", .bool, update: .push, doc: "ob sie gerade aufgeht."),
                S.field("closing", .bool, update: .push, doc: "ob sie gerade zugeht."),
            ],
            validIn: ["surfaceBody", "elementBody"]
        ),
        ContextRootSchema(
            name: "surfaces",
            fields: [
                S.field("open", .bool, update: .push, doc: "ob eine andere Oberfläche offen ist."),
                S.field("width", .number, update: .push, doc: "ihre Breite."),
                S.field("height", .number, update: .push, doc: "ihre Höhe."),
            ],
            validIn: ["surfaceBody", "elementBody"]
        ),
        ContextRootSchema(
            name: "screen",
            fields: [
                S.field("id", .string, update: .push, doc: "stabiler Schlüssel des Bildschirms."),
                S.field("name", .string, update: .push, doc: "Name."),
                S.field("main", .bool, update: .push, doc: "ob es der Hauptbildschirm ist."),
                S.field("width", .number, update: .push, doc: "Breite."),
                S.field("height", .number, update: .push, doc: "Höhe."),
                S.field("notch", .bool, update: .push, doc: "ob eine Notch vorhanden ist."),
            ],
            validIn: ["surfaceBody", "elementBody"]
        ),
        ContextRootSchema(
            name: "theme",
            fields: [
                S.field("id", .string, update: .push, doc: "Kennung."),
                S.field("name", .string, update: .push, doc: "Name."),
                S.field("appearance", .string, update: .push, doc: "hell oder dunkel."),
                S.field("dark", .bool, update: .push, doc: "ob dunkel."),
                S.field("set", .record, update: .push, doc: "welche Tokens das Theme setzt."),
            ],
            validIn: ["surfaceBody", "elementBody"]
        ),
        ContextRootSchema(
            name: "shell",
            fields: [
                S.field("version", .string, update: .once, doc: "Version der Shell."),
                S.field("features", .list, update: .once, doc: "bekannte Features."),
                S.field("config", .string, update: .push, doc: "Kennung der aktiven Config."),
                S.field("configs.id", .identifier, update: .push, doc: "Kennung einer wählbaren Config."),
                S.field("configs.name", .string, update: .push, doc: "Name einer wählbaren Config."),
                S.field("configs.source", .string, update: .push, doc: "Herkunft einer wählbaren Config."),
                S.field("themes.id", .string, update: .push, doc: "Kennung eines verfügbaren Themes."),
                S.field("themes.name", .string, update: .push, doc: "Name eines verfügbaren Themes."),
                S.field("themes.author", .string, update: .push, doc: "Autor eines verfügbaren Themes."),
                S.field("themes.description", .string, update: .push, doc: "Beschreibung eines verfügbaren Themes."),
                S.field("themes.issues", .list, update: .push, doc: "Hinweise zu einem verfügbaren Theme, als Liste von Texten."),
                S.field("hotkeys.chord", .string, update: .push, doc: "Tastenkombination."),
                S.field("hotkeys.ok", .bool, update: .push, doc: "ob die Kombination frei von Konflikten ist."),
                S.field("install-kind", .string, update: .once, doc: "dmg oder homebrew."),
                S.field("fresh-install", .bool, update: .once, doc: "ob es die erste Installation ist."),
                S.field("login-item", .bool, update: .push, doc: "ob die Shell als Anmeldeobjekt läuft."),
                S.field("login-item-available", .bool, update: .push, doc: "ob das Anmeldeobjekt verfügbar ist."),
                S.field("login-item-note", .string, nullable: true, update: .push, doc: "Hinweistext."),
                S.field("update.status", .enumeration(["idle", "checking", "available", "ready", "failed", "unavailable"]), update: .push, doc: "Update-Stand."),
                S.field("update.version", .string, update: .push, doc: "verfügbare Version."),
                S.field("update.notes-url", .string, update: .push, doc: "Adresse der Release-Notes."),
                S.field("update.last-check", .value, nullable: true, update: .push, doc: "Zeitpunkt der letzten Prüfung."),
                S.field("update.error", .string, nullable: true, update: .push, doc: "letzte Fehlermeldung."),
            ],
            validIn: ["topLevel", "surfaceBody", "elementBody", "actions", "menu", "commandCenterItems", "wmBlock"]
        ),
        ContextRootSchema(
            name: "event",
            fields: [],
            validIn: ["actions"]
        ),
        ContextRootSchema(
            name: "toast",
            fields: [
                S.field("title", .string, update: .push, doc: "Titel."),
                S.field("body", .string, update: .push, doc: "Text."),
                S.field("icon", .string, update: .push, doc: "Symbol."),
                S.field("kind", .string, update: .push, doc: "info, success, warning oder error."),
                S.field("id", .identifier, update: .once, doc: "Kennung der Meldung."),
                S.field("remaining", .number, update: .tick, doc: "Sekunden bis zum Verschwinden."),
                S.field("queued", .bool, update: .once, doc: "ob sie vor dem Erscheinen gewartet hat."),
            ],
            validIn: ["elementBody"]
        ),
    ]
}
