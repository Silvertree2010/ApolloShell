#if DEBUG
import AppKit
import ApolloShellCore
import SwiftUI

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

    /// Messaufbau fuer Gesten unter `scaleEffect`: dieselbe Struktur wie das
    /// Dashboard (`ScaledToFit` + `scaleEffect` um oben links, benannter
    /// Bezugsraum innen), Massstab 2, ein Feld an bekannter Stelle. Ein Zug
    /// ueber 200 Fensterpunkte muss im Bezugsraum 100 ergeben.
    private func probeScaledDrag() async {
        var translation: CGSize?
        var location: CGPoint?
        let view = ScaledToFit(scale: 2) {
            ZStack(alignment: .topLeading) {
                Color.blue.frame(width: 50, height: 50)
                    .padding(.leading, 20).padding(.top, 20)
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("probe"))
                        .onEnded { value in
                            translation = value.translation
                            location = value.startLocation
                        })
            }
            .frame(width: 200, height: 100, alignment: .topLeading)
            .coordinateSpace(name: "probe")
            .scaleEffect(2, anchor: .topLeading)
        }
        let hosting = FirstMouseHostingView(rootView: view)
        let panel = ShellPanel(size: hosting.fittingSize, level: .normal, behavior: [.canJoinAllSpaces])
        panel.contentView = hosting
        panel.setFrameOrigin(NSPoint(x: 100, y: 100))
        panel.orderFrontRegardless()
        await wait(0.2)
        note("Messaufbau: Fenster \(r(panel.frame)), Host \(r(hosting.frame))")
        func send(_ type: NSEvent.EventType, _ p: CGPoint) {
            let loc = hosting.convert(NSPoint(x: p.x, y: p.y), to: nil)
            if let e = NSEvent.mouseEvent(with: type, location: loc, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                panel.sendEvent(e)
            }
        }
        send(.leftMouseDown, CGPoint(x: 90, y: 90))
        for step in 1...8 { send(.leftMouseDragged, CGPoint(x: 90 + 25 * CGFloat(step), y: 90)) }
        send(.leftMouseUp, CGPoint(x: 290, y: 90))
        await wait(0.2)
        note("Messaufbau: Zug 200 Fensterpunkte → Uebersetzung \(translation.map { "\($0.width)" } ?? "keine Geste"), Start \(location.map { "\($0)" } ?? "-")")
        check(translation.map { abs($0.width - 100) < 1 } ?? false,
              "Gesten unter scaleEffect rechnen im unskalierten Bezugsraum (erwartet 100)")
        panel.orderOut(nil)
    }

    /// Griff, Antippen (Popover am Widget), Minus - bei echtem Massstab.
    private func widgetHandles(_ id: WidgetInstance.ID) async {
        guard let page = dashboardEditor.debugPageRectInHost,
              let frame = dashboardEditor.page?.widgets.first(where: { $0.id == id })?.frame else { return }
        let scale = dashboard.debugScale
        func host(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: page.minX + x * scale, y: page.minY + y * scale)
        }
        // Griff unten rechts (Mitte 17 Punkte vor der Ecke) um 100 x 120 ziehen:
        // Hoehe springt auf 250, Breite 110 + 100 = 210.
        let handle = host(frame.maxX - 17, frame.maxY - 17)
        dashboard.debugDrag(from: handle, to: CGPoint(x: handle.x + 100 * scale, y: handle.y + 120 * scale))
        await wait(0.4)
        let resized = dashboardEditor.page?.widgets.first(where: { $0.id == id })?.frame
        check(resized.map { $0.width == frame.width + 100 && $0.height == 250 && $0.x == frame.x } ?? false,
              "Griff aendert die Groesse (vorher \(Int(frame.width))x\(Int(frame.height)), nachher \(resized.map { "\(Int($0.width))x\(Int($0.height))" } ?? "-"))")
        guard let current = resized else { return }

        // Antippen: Popover mit den Optionen, und zwar neben diesem Widget.
        dashboardEditor.optionsWidgetID = nil
        dashboard.debugClick(at: host(current.x + current.width / 2, current.y + current.height / 2))
        await wait(0.6)
        check(dashboardEditor.optionsWidgetID == id, "Antippen oeffnet die Optionen")
        let popover = NSApp.windows.first { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
        let widgetOnScreen = dashboard.debugScreenRect(ofHostRect: CGRect(x: page.minX + current.x * scale, y: page.minY + current.y * scale,
                                                                             width: current.width * scale, height: current.height * scale))
        note("Popover \(r(popover?.frame)), Widget auf dem Bildschirm \(r(widgetOnScreen))")
        if let popover, let widgetOnScreen {
            let besideRight = abs(popover.frame.minX - widgetOnScreen.maxX) < 40
            let verticallyNear = popover.frame.minY < widgetOnScreen.maxY && popover.frame.maxY > widgetOnScreen.minY
            check(besideRight && verticallyNear, "Popover steht rechts neben dem Widget")
        } else {
            check(false, "Popover erscheint")
        }
        dashboardEditor.optionsWidgetID = nil
        await wait(0.4)

        // Minus oben links (Mitte genau auf der Ecke).
        dashboard.debugClick(at: host(current.x, current.y))
        await wait(0.5)
        check(!(dashboardEditor.page?.widgets.contains { $0.id == id } ?? true), "Minus entfernt das Widget")
    }

    /// Esc von innen nach aussen: Auswahl, Umbenennen, Galerie, Rueckfrage,
    /// erst dann Abbrechen.
    private func escapeOrder(on screen: NSScreen) async {
        editor.begin(screen: screen)
        await wait(0.5)
        let page = dashboardEditor.page
        dashboardEditor.selectedWidgetID = page?.widgets.first?.id
        dashboardEditor.optionsWidgetID = page?.widgets.first?.id
        editor.galleryVisible = true
        editor.debugEscape()
        check(dashboardEditor.selectedWidgetID == nil && dashboardEditor.optionsWidgetID == nil && editor.galleryVisible,
              "Esc 1: nur Auswahl und Optionen zu, Galerie bleibt")
        dashboardEditor.renamingPageID = page?.id
        editor.debugEscape()
        check(dashboardEditor.renamingPageID == nil && editor.galleryVisible, "Esc 2: Umbenennen zu, Galerie bleibt")
        editor.debugEscape()
        check(!editor.galleryVisible && editor.isEditing, "Esc 3: Galerie zu, Modus bleibt")
        dashboardEditor.addPage()
        editor.debugEscape()
        check(editor.pendingCancelConfirmation && editor.isEditing, "Esc 4 mit Aenderungen: Rueckfrage statt Abbruch")
        editor.debugEscape()
        check(!editor.pendingCancelConfirmation && editor.isEditing, "Esc 5: Rueckfrage zu, weiter bearbeiten")
        editor.debugEscape()
        editor.confirmCancel()
        check(!editor.isEditing, "Verwerfen beendet den Modus")
        await wait(0.8)
        editor.begin(screen: screen)
        await wait(0.3)
        editor.debugEscape()
        check(!editor.isEditing, "Esc ohne Aenderungen bricht sofort ab")
        await wait(0.8)
        dashboard.debugClose()
        utilities.debugClose()
        await wait(0.5)
    }

    /// Kontrollzentrum: WLAN antippen (waehlt, kein Popover), Minus an WLAN
    /// und an einer Karte, danach Link-Knopf antippen (Optionen). Rahmen
    /// immer frisch: waechst das Panel (neue Reihe), veralten gemeldete
    /// Fensterkoordinaten.
    private func controlCentre(on screen: NSScreen) async {
        editor.begin(screen: screen)
        await wait(0.8)
        guard let wifi = editor.utilities?.layout.toggles.first(where: { $0.kind == .wifi }),
              let wifiRect = editor.debugUtilitiesRects[wifi.id] else {
            check(false, "WLAN-Kachel im Kontrollzentrum gefunden")
            editor.cancel()
            return
        }
        editor.selectedToggleID = nil
        utilities.debugClick(fromTop: CGPoint(x: wifiRect.midX, y: wifiRect.midY))
        await wait(0.6)
        let wifiPopover = NSApp.windows.first { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
        check(editor.selectedToggleID == wifi.id && wifiPopover == nil, "WLAN antippen waehlt, ohne leeres Popover")
        editor.selectedToggleID = nil
        await wait(0.3)
        // Minus eines Knopfs: Mitte 1 Punkt rechts, 3 unter der Ecke oben links.
        utilities.debugClick(fromTop: CGPoint(x: wifiRect.minX + 1, y: wifiRect.minY + 3))
        await wait(0.5)
        check(!(editor.utilities?.layout.toggles.contains { $0.id == wifi.id } ?? true), "Minus entfernt den WLAN-Knopf")
        await wait(0.3)
        if let card = editor.debugUtilitiesRects["card:keepAwake"] {
            utilities.debugClick(fromTop: CGPoint(x: card.minX + 2, y: card.minY + 2))
            await wait(0.5)
            check(editor.utilities?.layout.isEnabled(.keepAwake) == false, "Minus blendet die Karte „Wach halten“ aus")
        } else {
            check(false, "Karte „Wach halten“ gefunden")
        }
        editor.cancel()
        await wait(0.8)

        editor.begin(screen: screen)
        await wait(0.6)
        guard let link = editor.addToggle(.openLink) else { check(false, "Link-Knopf einfuegen"); return }
        editor.selectedToggleID = nil
        await wait(0.8)
        utilities.debugRelayout()
        await wait(0.2)
        if let linkRect = editor.debugUtilitiesRects[link] {
            utilities.debugClick(fromTop: CGPoint(x: linkRect.midX, y: linkRect.midY))
            await wait(0.6)
            let popover = NSApp.windows.first { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
            note("Link: Rahmen \(r(linkRect)), Fensterhoehe \(Int(utilities.debugWindowHeight)), gewaehlt \(String(describing: editor.selectedToggleID)), Popover \(r(popover?.frame))")
            note("alle Kacheln: " + (editor.utilities?.layout.toggles.map { "\($0.id)=\(r(editor.debugUtilitiesRects[$0.id]))" }.joined(separator: " ") ?? ""))
            check(editor.selectedToggleID == link && popover != nil, "Link-Knopf antippen zeigt seine Optionen")
        } else {
            check(false, "Link-Kachel gefunden")
        }
        editor.cancel()
        await wait(0.8)
        dashboard.debugClose()
        utilities.debugClose()
        await wait(0.5)
    }

    /// Normaler Betrieb ohne Bearbeiten: Knoepfe der Leiste oeffnen die
    /// passende Seite, zweiter Klick schliesst, Leistung misst nur auf der
    /// Leistungs-Seite.
    private func normalUse() async {
        guard let pages = store.settings.dashboardPages else { check(false, "Seiten da"); return }
        for (tab, template) in [(DashboardTab.media, PageTemplate.media), (.performance, .performance), (.weather, .weather), (.dashboard, .overview)] {
            dashboard.show(tab: tab)
            await wait(0.5)
            let expected = pages.pages.first { $0.template == template }?.id
            check(dashboard.debugIsOpen && dashboard.debugShownPage == expected, "Leistenknopf \(tab.rawValue) oeffnet seine Seite")
            check(dashboard.debugShowsPerformance == (template == .performance), "Leistungsmessung nur auf der Leistungs-Seite (\(tab.rawValue))")
            dashboard.show(tab: tab)
            await wait(0.5)
            check(!dashboard.debugIsOpen, "Zweiter Klick auf \(tab.rawValue) schliesst")
        }
        dashboard.toggle()
        await wait(0.5)
        check(dashboard.debugIsOpen, "Dashboard-Kuerzel oeffnet")
        dashboard.toggle()
        await wait(0.5)
        check(!dashboard.debugIsOpen, "Dashboard-Kuerzel schliesst")
    }

    private func scenario() async {
        await normalUse()
        await probeScaledDrag()
        for screen in NSScreen.screens {
            note("Bildschirm \(r(screen.frame)), sichtbar \(r(screen.visibleFrame))")
        }
        for screen in NSScreen.screens {
            await pass(on: screen)
        }
        // Grenzfall: Regler auf 150 % - das Dashboard fuellt fast die Hoehe.
        if let screen = NSScreen.screens.first {
            store.settings.dashboardScale = 1.5
            editor.begin(screen: screen)
            await wait(0.8)
            editor.galleryVisible = true
            await wait(0.8)
            let dashboardFrame = dashboard.openFrame
            let gallery = windows.debugGalleryFrame
            let toolbar = windows.debugToolbarFrame
            note("150 %: Dashboard \(r(dashboardFrame)), Galerie \(r(gallery)), Leiste \(r(toolbar))")
            check(gallery.map(screen.frame.contains) ?? false, "150 %: Galerie bleibt ganz auf dem Bildschirm")
            check(toolbar.map(screen.frame.contains) ?? false, "150 %: Werkzeugleiste bleibt ganz auf dem Bildschirm")
            if let gallery, let toolbar { check(!gallery.intersects(toolbar), "150 %: Galerie frei von der Werkzeugleiste") }
            editor.cancel()
            await wait(0.8)
            dashboard.debugClose()
            utilities.debugClose()
            store.settings.dashboardScale = 1
            await wait(0.5)
        }
        if let screen = NSScreen.screens.first {
            await escapeOrder(on: screen)
            await controlCentre(on: screen)
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
        // Passt der Inhalt des Kontrollzentrums im Bearbeiten ins Panel?
        if let layout = editor.utilities?.layout {
            let content = NSHostingView(rootView: EditableUtilitiesView(editor: editor, layout: layout).shellTheme(nil))
            let needed = content.fittingSize.height
            check(needed <= utilities.height + 1,
                  "Kontrollzentrum im Bearbeiten passt ins Panel (Inhalt \(Int(needed)), Panel \(Int(utilities.height)))")
        }
        let levels = windows.debugLevels
        let drawerLevels = [dashboard.debugLevel, utilities.debugLevel].compactMap { $0 }
        check(drawerLevels.allSatisfy { $0 > levels.scrim && $0 < levels.controls },
              "Ebenen: Schleier \(levels.scrim) < Kantenfenster \(drawerLevels) < Leiste/Galerie \(levels.controls)")
        check(levels.scrim > NSWindow.Level.mainMenu.rawValue, "Schleier ueber Menueleiste und Dock")
        check(windows.debugPanelLevels.allSatisfy { $0 == levels.scrim || $0 == levels.controls },
              "Panels stehen wirklich auf ihrer Ebene \(windows.debugPanelLevels)")

        // Klick auf „+“ der Werkzeugleiste (18 Rand + halbe Knopfbreite 17,
        // halbe Hoehe) - kommt er an, geht die Galerie auf.
        if let toolbar = windows.debugToolbarFrame {
            windows.debugClickToolbar(fromTopLeft: NSPoint(x: 35, y: toolbar.height / 2))
            await wait(0.2)
            check(editor.galleryVisible, "Klick auf + der Werkzeugleiste kommt an")
        }
        editor.galleryVisible = true
        await wait(0.9)
        let gallery = windows.debugGalleryFrame
        check(gallery.map(screen.frame.contains) ?? false, "Galerie ganz auf dem Bildschirm \(r(gallery))")
        if let gallery, let dashboardFrame { check(!gallery.intersects(dashboardFrame), "Galerie frei vom Dashboard") }
        if let gallery, let utilitiesFrame { check(!gallery.intersects(utilitiesFrame), "Galerie frei vom Kontrollzentrum") }
        if let gallery, let toolbar = windows.debugToolbarFrame { check(!gallery.intersects(toolbar), "Galerie frei von der Werkzeugleiste") }

        // Volle Seite (Uebersicht): Klick auf Uhr in der Galerie -> Hinweis,
        // Galerie waechst, bleibt aber frei vom Dashboard.
        if let gallery = windows.debugGalleryFrame, dashboardEditor.page?.template == .overview {
            let column = (gallery.width - 32 - 7 * 10) / 8
            let before = dashboardEditor.page?.widgets.count ?? 0
            windows.debugClickGallery(fromTopLeft: NSPoint(x: 16 + column * 2.5 + 20, y: 16 + 36 + 12 + 20 + 12 + 30))
            await wait(0.4)
            check(editor.galleryNotice != nil && dashboardEditor.page?.widgets.count == before,
                  "Volle Seite: Galerie-Klick zeigt „Kein Platz“ statt einzufuegen")
            if let grown = windows.debugGalleryFrame, let dashboardFrame {
                check(!grown.intersects(dashboardFrame), "Galerie mit Hinweis bleibt frei vom Dashboard \(r(grown))")
            }
        }
        // Reiter Kontrollzentrum: Klick auf „Bildschirm aus“ (14. Kachel, zweite
        // Reihe, sechste Spalte) fuegt den Knopf an.
        editor.galleryTab = .controlCentre
        await wait(0.4)
        if let gallery = windows.debugGalleryFrame {
            let column = (gallery.width - 32 - 7 * 10) / 8
            let tileHeight: CGFloat = 73
            windows.debugClickGallery(fromTopLeft: NSPoint(x: 16 + 5 * (column + 10) + column / 2,
                                                           y: 16 + 36 + 12 + 20 + 12 + tileHeight + 10 + tileHeight / 2))
            await wait(0.4)
            check(editor.utilities?.layout.toggles.contains { $0.kind == .displaySleep } ?? false,
                  "Galerie Kontrollzentrum: Klick fuegt „Bildschirm aus“ an")
        }
        editor.galleryTab = .dashboard
        await wait(0.3)

        // Aendern und Fertig.
        let pageCount = dashboardEditor.session?.pages.pages.count ?? 0
        let newPage = dashboardEditor.addPage()
        // Klick auf die erste Galerie-Kachel (Wetter): 16 Rand + halbe
        // Spalte, unter Reitern (36) und Haken (≈20) mit 12er Abstaenden.
        if let gallery = windows.debugGalleryFrame {
            let column = (gallery.width - 32 - 7 * 10) / 8
            windows.debugClickGallery(fromTopLeft: NSPoint(x: 16 + column / 2, y: 16 + 36 + 12 + 20 + 12 + 30))
            await wait(0.2)
            check(dashboardEditor.page?.widgets.contains { $0.kind == .weather } ?? false,
                  "Klick auf eine Galerie-Kachel fuegt das Widget ein")
        }
        let clock = dashboardEditor.addAtFirstFreeSpot(.clock)
        check(clock != nil, "Uhr auf neuer Seite eingefuegt")
        // Ziehen bei Massstab ≠ 1: die Uhr um 100 Referenzpunkte nach rechts.
        await wait(0.3)
        if let clock, let before = dashboardEditor.page?.widgets.first(where: { $0.id == clock })?.frame,
           let page = dashboardEditor.debugPageRectInHost {
            let scale = dashboard.debugScale
            let start = CGPoint(x: page.minX + (before.x + before.width / 2) * scale,
                                y: page.minY + (before.y + before.height / 2) * scale)
            note("Seite im Host \(r(page)), Start \(Int(start.x)),\(Int(start.y)), Massstab \(scale)")
            dashboardEditor.selectedWidgetID = nil
            dashboard.debugDrag(from: start, to: CGPoint(x: start.x + 100 * scale, y: start.y))
            await wait(0.4)
            note("nach dem Zug gewaehlt: \(dashboardEditor.selectedWidgetID == clock ? "die Uhr" : String(describing: dashboardEditor.selectedWidgetID))")
            let after = dashboardEditor.page?.widgets.first(where: { $0.id == clock })?.frame
            check(after.map { abs($0.x - (before.x + 100)) <= 1 && $0.y == before.y } ?? false,
                  "Ziehen bei Massstab \(String(format: "%.3f", scale)): 100 Punkte werden 100 (vorher x \(Int(before.x)), nachher \(after.map { String(Int($0.x)) } ?? "-"))")
            await widgetHandles(clock)
        } else {
            check(false, "Ziehen: Seite oder Uhr nicht gefunden")
        }
        let toggle = editor.addToggle(.openLink)
        check(toggle != nil, "Knopf „Link öffnen“ im Kontrollzentrum eingefuegt")
        // „Fertig“ per Klick: rechter Knopf der Werkzeugleiste.
        if let toolbar = windows.debugToolbarFrame {
            windows.debugClickToolbar(fromTopLeft: NSPoint(x: toolbar.width - 18 - 25, y: toolbar.height / 2))
            await wait(0.2)
        }
        if editor.isEditing {
            check(false, "Klick auf Fertig kommt an")
            editor.done()
        } else {
            check(true, "Klick auf Fertig kommt an")
        }
        await wait(0.1)
        check(!editor.isEditing, "Modus endet mit Fertig")
        check(store.settings.dashboardPages?.pages.count == pageCount + 1, "Fertig speichert die neue Seite")
        check(store.settings.utilities.layout.toggles.contains { $0.kind == .openLink }, "Fertig speichert den neuen Knopf")
        check(dashboard.debugShownPage == newPage, "Nach Fertig bleibt das Dashboard auf der bearbeiteten Seite")
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

/// Selbsttest: meldet den eigenen Rahmen in Fensterkoordinaten (AppKit,
/// unten links) - genauer als SwiftUI-Bezugsraeume, wenn das Hosting-Fenster
/// anders geschnitten ist als der Inhalt.
struct DebugWindowRectReporter: NSViewRepresentable {
    let report: (NSRect) -> Void

    func makeNSView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.report = report
        return view
    }

    func updateNSView(_ view: ReporterView, context: Context) {
        view.report = report
        view.needsLayout = true
    }

    final class ReporterView: NSView {
        var report: (NSRect) -> Void = { _ in }
        override func layout() {
            super.layout()
            // Abstand zur Oberkante statt zur Unterkante: waechst das Fenster
            // nach oben (Kontrollzentrum bekommt eine Reihe), bleibt der
            // Inhalt oben stehen, ohne dass `layout()` erneut kommt.
            let rect = convert(bounds, to: nil)
            let height = window?.frame.height ?? 0
            report(NSRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height))
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif
