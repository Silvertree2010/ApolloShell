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
                S.field("configs", .list, update: .push, doc: "wählbare Configs."),
                S.field("themes", .list, update: .push, doc: "verfügbare Themes."),
                S.field("hotkeys", .list, update: .push, doc: "globale Tastenkürzel mit Konfliktstatus."),
                S.field("install-kind", .string, update: .once, doc: "dmg oder homebrew."),
                S.field("fresh-install", .bool, update: .once, doc: "ob es die erste Installation ist."),
                S.field("login-item", .bool, update: .push, doc: "ob die Shell als Anmeldeobjekt läuft."),
                S.field("login-item-available", .bool, update: .push, doc: "ob das Anmeldeobjekt verfügbar ist."),
                S.field("login-item-note", .string, nullable: true, update: .push, doc: "Hinweistext."),
                S.field("update", .record, update: .push, doc: "Update-Status."),
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
