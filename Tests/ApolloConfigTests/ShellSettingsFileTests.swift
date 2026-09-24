import Testing
@testable import ApolloConfig

@Suite("ShellSettingsFile parse")
struct ShellSettingsFileParseTests {
    @Test("Vorgaben ohne Datei")
    func defaults() {
        let (settings, diagnostics) = ShellSettingsFile.parse("", file: "settings.kdl")
        #expect(settings == ShellSettingsFile())
        #expect(diagnostics.isEmpty)
    }

    @Test("Jeder Knoten gueltig")
    func validNodes() {
        let text = """
        config "apolloshell-default"
        theme "Afterglow"
        updates auto-check=#true auto-install=#false
        crash-reports "always"
        editor "code -g {file}:{line}:{column}"
        """
        let (settings, diagnostics) = ShellSettingsFile.parse(text, file: "settings.kdl")
        #expect(settings.config == "apolloshell-default")
        #expect(settings.theme == "Afterglow")
        #expect(settings.autoCheckUpdates == true)
        #expect(settings.autoInstallUpdates == false)
        #expect(settings.crashReports == "always")
        #expect(settings.editor == "code -g {file}:{line}:{column}")
        #expect(diagnostics.isEmpty)
    }

    @Test("theme #null ist kein Theme")
    func themeNull() {
        let (settings, diagnostics) = ShellSettingsFile.parse("theme #null", file: "settings.kdl")
        #expect(settings.theme == nil)
        #expect(diagnostics.isEmpty)
    }

    @Test("Ungueltiger Knoteninhalt ergibt Warnung")
    func invalidNodeContent() {
        let (settings, diagnostics) = ShellSettingsFile.parse("config 5", file: "settings.kdl")
        #expect(settings.config == nil)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
    }

    @Test("Fehlender Knoten ist keine Warnung")
    func missingNode() {
        let (settings, diagnostics) = ShellSettingsFile.parse("theme \"Afterglow\"", file: "settings.kdl")
        #expect(settings.config == nil)
        #expect(diagnostics.isEmpty)
    }

    @Test("Unbekannter Knoten ist Warnung")
    func unknownNode() {
        let (_, diagnostics) = ShellSettingsFile.parse("mystery-node 1", file: "settings.kdl")
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
        #expect(diagnostics[0].message.contains("mystery-node"))
    }

    @Test("Doppelter Knoten: letzter gilt, mit Warnung")
    func duplicateNode() {
        let text = """
        config "a"
        config "b"
        """
        let (settings, diagnostics) = ShellSettingsFile.parse(text, file: "settings.kdl")
        #expect(settings.config == "b")
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
    }

    @Test("Kaputte Datei ergibt Vorgaben plus Warnung")
    func brokenFile() {
        let (settings, diagnostics) = ShellSettingsFile.parse("config \"unterminated", file: "settings.kdl")
        #expect(settings == ShellSettingsFile())
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
    }
}

@Suite("ShellSettingsFile updating")
struct ShellSettingsFileUpdatingTests {
    @Test("Neue Datei aus leerem Text")
    func newFileFromEmptyText() throws {
        let updated = try ShellSettingsFile.updating("", file: "settings.kdl", set: .config("apolloshell-default"))
        let (settings, diagnostics) = ShellSettingsFile.parse(updated, file: "settings.kdl")
        #expect(settings.config == "apolloshell-default")
        #expect(diagnostics.isEmpty)
    }

    @Test("config setzen behaelt Geschwister byte-gleich")
    func settingConfigKeepsSiblingsByteEqual() throws {
        let text = """
        // comment
        theme "Afterglow"
        config "old"
        editor "code"
        """
        let updated = try ShellSettingsFile.updating(text, file: "settings.kdl", set: .config("new"))
        #expect(updated.contains("// comment"))
        #expect(updated.contains("theme \"Afterglow\""))
        #expect(updated.contains("editor \"code\""))
        #expect(updated.contains("config \"new\""))
        #expect(!updated.contains("\"old\""))
        let (settings, _) = ShellSettingsFile.parse(updated, file: "settings.kdl")
        #expect(settings.config == "new")
        #expect(settings.theme == "Afterglow")
        #expect(settings.editor == "code")
    }

    @Test("config nil entfernt den Knoten")
    func configNilRemovesNode() throws {
        let text = "config \"old\"\ntheme \"Afterglow\"\n"
        let updated = try ShellSettingsFile.updating(text, file: "settings.kdl", set: .config(nil))
        let (settings, _) = ShellSettingsFile.parse(updated, file: "settings.kdl")
        #expect(settings.config == nil)
        #expect(!updated.contains("config"))
        #expect(updated.contains("theme \"Afterglow\""))
    }

    @Test("config nil ohne Knoten aendert nichts")
    func configNilWithoutNodeIsNoop() throws {
        let text = "theme \"Afterglow\"\n"
        let updated = try ShellSettingsFile.updating(text, file: "settings.kdl", set: .config(nil))
        #expect(updated == text)
    }

    @Test("theme nil schreibt #null wenn der Knoten existiert")
    func themeNilWritesNullWhenPresent() throws {
        let text = "theme \"Afterglow\"\n"
        let updated = try ShellSettingsFile.updating(text, file: "settings.kdl", set: .theme(nil))
        let (settings, _) = ShellSettingsFile.parse(updated, file: "settings.kdl")
        #expect(settings.theme == nil)
        #expect(updated.contains("#null"))
    }

    @Test("theme nil ohne Knoten aendert nichts")
    func themeNilWithoutNodeIsNoop() throws {
        let text = "config \"apolloshell-default\"\n"
        let updated = try ShellSettingsFile.updating(text, file: "settings.kdl", set: .theme(nil))
        #expect(updated == text)
    }

    @Test("updates setzen")
    func settingUpdates() throws {
        let updated = try ShellSettingsFile.updating("", file: "settings.kdl", set: .updates(autoCheck: false, autoInstall: true))
        let (settings, _) = ShellSettingsFile.parse(updated, file: "settings.kdl")
        #expect(settings.autoCheckUpdates == false)
        #expect(settings.autoInstallUpdates == true)
    }

    @Test("crash-reports setzen")
    func settingCrashReports() throws {
        let updated = try ShellSettingsFile.updating("", file: "settings.kdl", set: .crashReports("never"))
        let (settings, _) = ShellSettingsFile.parse(updated, file: "settings.kdl")
        #expect(settings.crashReports == "never")
    }

    @Test("editor setzen und wieder entfernen")
    func settingAndRemovingEditor() throws {
        let withEditor = try ShellSettingsFile.updating("", file: "settings.kdl", set: .editor("code -g {file}"))
        let (settingsWithEditor, _) = ShellSettingsFile.parse(withEditor, file: "settings.kdl")
        #expect(settingsWithEditor.editor == "code -g {file}")
        let withoutEditor = try ShellSettingsFile.updating(withEditor, file: "settings.kdl", set: .editor(nil))
        let (settingsWithoutEditor, _) = ShellSettingsFile.parse(withoutEditor, file: "settings.kdl")
        #expect(settingsWithoutEditor.editor == nil)
    }

    @Test("CRLF bleibt CRLF, auch fuer neue Knoten")
    func crlfStaysCRLF() throws {
        let text = "theme \"Afterglow\"\r\nconfig \"old\"\r\n"
        let updated = try ShellSettingsFile.updating(text, file: "settings.kdl", set: .config("new"))
        #expect(updated.contains("\r\n"))
        #expect(!updated.contains("Afterglow\"\nconfig"))
        let (settings, _) = ShellSettingsFile.parse(updated, file: "settings.kdl")
        #expect(settings.config == "new")
    }

    @Test("BOM am Dateianfang bleibt erhalten")
    func bomIsPreserved() throws {
        let text = "\u{FEFF}config \"old\"\n"
        let updated = try ShellSettingsFile.updating(text, file: "settings.kdl", set: .config("new"))
        #expect(updated.hasPrefix("\u{FEFF}"))
        let (settings, _) = ShellSettingsFile.parse(updated, file: "settings.kdl")
        #expect(settings.config == "new")
    }

    @Test("Emoji und Tabs vor dem geaenderten Knoten bleiben gleich")
    func emojiAndTabsBeforeChangedNodeStay() throws {
        let text = "theme \"\u{1F680} Afterglow\"\n\tconfig \"old\"\n"
        let updated = try ShellSettingsFile.updating(text, file: "settings.kdl", set: .config("new"))
        #expect(updated.contains("\u{1F680} Afterglow"))
        #expect(updated.contains("\tconfig \"new\""))
    }

    @Test("Kommentar in derselben Zeile hinter dem Knoten bleibt stehen")
    func trailingCommentStays() throws {
        let text = "config \"old\" // pick one\n"
        let updated = try ShellSettingsFile.updating(text, file: "settings.kdl", set: .config("new"))
        #expect(updated.contains("// pick one"))
        let (settings, _) = ShellSettingsFile.parse(updated, file: "settings.kdl")
        #expect(settings.config == "new")
    }

    @Test("Datei ohne abschliessenden Zeilenumbruch")
    func fileWithoutTrailingNewline() throws {
        let text = "config \"old\""
        let updated = try ShellSettingsFile.updating(text, file: "settings.kdl", set: .config("new"))
        let (settings, _) = ShellSettingsFile.parse(updated, file: "settings.kdl")
        #expect(settings.config == "new")
    }

    @Test("Nicht parsbare Datei wird nie ueberschrieben")
    func unparsableFileIsNeverOverwritten() {
        let text = "config \"unterminated"
        #expect(throws: (any Error).self) {
            try ShellSettingsFile.updating(text, file: "settings.kdl", set: .config("new"))
        }
    }

    @Test("Pfade mit Leerzeichen im editor-Befehl")
    func pathsWithSpaces() throws {
        let updated = try ShellSettingsFile.updating("", file: "settings.kdl", set: .editor("open -a \"Visual Studio Code\" {file}"))
        let (settings, _) = ShellSettingsFile.parse(updated, file: "settings.kdl")
        #expect(settings.editor == "open -a \"Visual Studio Code\" {file}")
    }

    @Test("Einrueckung der Geschwister fuer neue Knoten")
    func newNodeMatchesSiblingIndentation() throws {
        let text = "    theme \"Afterglow\"\n"
        let updated = try ShellSettingsFile.updating(text, file: "settings.kdl", set: .config("new"))
        #expect(updated.contains("    config \"new\""))
    }
}
