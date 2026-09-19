#if DEBUG
import AppKit
import ApolloShellCore

/// Unsichtbarer Selbsttest des globalen Bearbeitungsmodus:
/// `ApolloShell --selftest-edit <Datei>` baut Dashboard, Kontrollzentrum und
/// die Fenster des Modus mit einer Einstellung nur im Speicher, spielt Beginnen,
/// Galerie, Hinzufuegen, Fertig, schnellen Neustart und Abbrechen durch und
/// schreibt, was stimmt und was nicht, in die Datei. Alle Panels bleiben
/// durchsichtig und klickdurchlaessig (`ShellPanel`), Esc und Maus-
/// Ueberwachung bleiben aus - so laeuft er neben der echten ApolloShell,
/// ohne den Bildschirm anzufassen. Nur in Debug-Bauten.
@MainActor
enum EditModeSelfTest {
    static var invisible = false
    private static var harness: EditModeSelfTestHarness?

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--selftest-edit"), index + 1 < args.count else { return }
        invisible = true
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let harness = EditModeSelfTestHarness(output: URL(fileURLWithPath: args[index + 1]))
        self.harness = harness
        DispatchQueue.main.async { harness.run() }
        app.run()
    }
}

@MainActor
private final class EditModeSelfTestHarness {
    private let output: URL
    private var lines: [String] = []
    private var failures = 0
    private let store: ShellSettingsStore
    private let dashboardEditor: DashboardEditor
    private let editor: ShellEditor
    private let dashboard: Dashboard
    private let utilities: UtilitiesPanel
    private let windows: EditModeWindows

    init(output: URL) {
        self.output = output
        var settings = ShellSettings()
        settings.dashboardPages = DashboardPages(pages: DashboardPages.defaultPages(
            places: .empty, hasBattery: PerformanceSampler.hasInternalBattery))
        store = .preview(settings)
        dashboardEditor = DashboardEditor(store: store)
        editor = ShellEditor(store: store, dashboard: dashboardEditor)
        dashboard = Dashboard(settings: store, editor: dashboardEditor)
        utilities = UtilitiesPanel(settings: store, editor: editor)
        windows = EditModeWindows(editor: editor)
        editor.dashboardStartPageID = { [weak dashboard] in dashboard?.currentPageID }
        windows.utilitiesFrame = { [weak utilities] in utilities?.openFrame }
        windows.dashboardFrame = { [weak dashboard] in dashboard?.openFrame }
        utilities.onHeightChange = { [weak windows] _ in windows?.utilitiesHeightChanged() }
    }

    func run() {
        Task { @MainActor in
            await scenario()
            lines.append(failures == 0 ? "ALLES OK" : "\(failures) FEHLER")
            try? lines.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
            exit(failures == 0 ? 0 : 1)
        }
    }

    private func check(_ ok: Bool, _ what: String) {
        lines.append((ok ? "ok     " : "FEHLER ") + what)
        if !ok { failures += 1 }
    }

    private func note(_ text: String) { lines.append("       " + text) }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func r(_ rect: NSRect?) -> String {
        guard let rect else { return "-" }
        return "(\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height)))"
    }

    private func scenario() async {
        for screen in NSScreen.screens {
            note("Bildschirm \(r(screen.frame)), sichtbar \(r(screen.visibleFrame))")
        }
        for screen in NSScreen.screens {
            await pass(on: screen)
        }
    }

    /// Ein ganzer Durchgang auf einem Bildschirm.
    private func pass(on screen: NSScreen) async {
        note("--- Durchgang auf \(r(screen.frame))")
        let before = store.settings
        editor.begin(screen: screen)
        await wait(0.9)
        check(editor.isEditing, "Modus laeuft nach Beginnen")
        let dashboardFrame = dashboard.openFrame
        let utilitiesFrame = utilities.openFrame
        check(dashboardFrame.map(screen.frame.intersects) ?? false, "Dashboard offen auf diesem Bildschirm \(r(dashboardFrame))")
        check(utilitiesFrame.map(screen.frame.intersects) ?? false, "Kontrollzentrum offen auf diesem Bildschirm \(r(utilitiesFrame))")
        check(windows.debugVisibleScrims == NSScreen.screens.count,
              "Schleier auf allen \(NSScreen.screens.count) Bildschirmen (\(windows.debugVisibleScrims))")
        let toolbar = windows.debugToolbarFrame
        check(toolbar.map(screen.frame.contains) ?? false, "Werkzeugleiste ganz auf dem Bildschirm \(r(toolbar))")
        if let toolbar, let utilitiesFrame {
            check(!toolbar.intersects(utilitiesFrame), "Werkzeugleiste frei vom Kontrollzentrum")
        }
        if let toolbar, let dashboardFrame {
            check(!toolbar.intersects(dashboardFrame), "Werkzeugleiste frei vom Dashboard")
        }
        let levels = windows.debugLevels
        let drawerLevels = [dashboard.debugLevel, utilities.debugLevel].compactMap { $0 }
        check(drawerLevels.allSatisfy { $0 > levels.scrim && $0 < levels.controls },
              "Ebenen: Schleier \(levels.scrim) < Kantenfenster \(drawerLevels) < Leiste/Galerie \(levels.controls)")
        check(levels.scrim > NSWindow.Level.mainMenu.rawValue, "Schleier ueber Menueleiste und Dock")
        check(windows.debugPanelLevels.allSatisfy { $0 == levels.scrim || $0 == levels.controls },
              "Panels stehen wirklich auf ihrer Ebene \(windows.debugPanelLevels)")

        editor.galleryVisible = true
        await wait(0.9)
        let gallery = windows.debugGalleryFrame
        check(gallery.map(screen.frame.contains) ?? false, "Galerie ganz auf dem Bildschirm \(r(gallery))")
        if let gallery, let dashboardFrame { check(!gallery.intersects(dashboardFrame), "Galerie frei vom Dashboard") }
        if let gallery, let utilitiesFrame { check(!gallery.intersects(utilitiesFrame), "Galerie frei vom Kontrollzentrum") }
        if let gallery, let toolbar = windows.debugToolbarFrame { check(!gallery.intersects(toolbar), "Galerie frei von der Werkzeugleiste") }

        // Aendern und Fertig.
        let pageCount = dashboardEditor.session?.pages.pages.count ?? 0
        dashboardEditor.addPage()
        let clock = dashboardEditor.addAtFirstFreeSpot(.clock)
        check(clock != nil, "Uhr auf neuer leerer Seite eingefuegt")
        let toggle = editor.addToggle(.openLink)
        check(toggle != nil, "Knopf „Link öffnen“ im Kontrollzentrum eingefuegt")
        editor.done()
        await wait(0.1)
        check(!editor.isEditing, "Modus endet mit Fertig")
        check(store.settings.dashboardPages?.pages.count == pageCount + 1, "Fertig speichert die neue Seite")
        check(store.settings.utilities.layout.toggles.contains { $0.kind == .openLink }, "Fertig speichert den neuen Knopf")
        await wait(0.9)
        check(windows.debugVisibleScrims == 0, "Schleier nach Fertig weg")
        check(windows.debugToolbarFrame == nil, "Werkzeugleiste nach Fertig weg")
        check(windows.debugGalleryFrame == nil, "Galerie nach Fertig weg")

        // Schneller Neustart: Ende und neuer Beginn kurz hintereinander.
        editor.begin(screen: screen)
        await wait(0.05)
        editor.cancel()
        await wait(0.05)
        editor.begin(screen: screen)
        await wait(0.9)
        check(windows.debugVisibleScrims == NSScreen.screens.count, "Schleier nach schnellem Neustart da")
        check(windows.debugToolbarFrame != nil, "Werkzeugleiste nach schnellem Neustart da")
        check(dashboard.openFrame != nil && utilities.openFrame != nil, "Panels nach schnellem Neustart offen")

        // Abbrechen verwirft.
        let saved = store.settings
        dashboardEditor.addPage()
        _ = editor.addToggle(.openApp)
        editor.cancel()
        await wait(0.9)
        check(store.settings == saved, "Abbrechen verwirft beide Arbeitskopien")
        check(windows.debugVisibleScrims == 0 && windows.debugToolbarFrame == nil, "Modus-Fenster nach Abbrechen weg")
        note("Dashboard nach Ende \(r(dashboard.openFrame)), Kontrollzentrum \(r(utilities.openFrame)) (zu, ausser der Zeiger steht dort)")
        store.settings = before
        dashboard.debugClose()
        utilities.debugClose()
        await wait(0.6)
    }
}
#endif
