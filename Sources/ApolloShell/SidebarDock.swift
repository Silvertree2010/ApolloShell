import AppKit
import ApolloShellCore
import ApplicationServices
import CoreGraphics
import Observation
import os
import SwiftUI
import UniformTypeIdentifiers

/// Dock in der Leiste (alle laufenden und angehefteten Apps, an Stelle des
/// aktiven Fensters) - mit dem Inhalt von Apples Dock: Finder, die dort
/// angehefteten Apps, nach einem Strich die uebrigen laufenden in
/// Startreihenfolge. Noch nicht dabei: zuletzt benutzte Apps
/// (show-recents), Ordner und der Papierkorb.
@MainActor
@Observable
final class SidebarDockModel {
    struct Entry: Identifiable, Equatable {
        let bundleID: String
        let name: String
        let icon: NSImage
        let pinned: Bool
        let running: Bool
        /// Ausgeblendet (⌘H): halb durchsichtig wie in Apples Dock mit
        /// "ausgeblendete Apps anzeigen".
        var hidden = false
        var id: String { bundleID }
    }

    private(set) var entries: [Entry] = []
    /// Bundle-ID der App im Vordergrund (leicht hinterlegt).
    private(set) var frontmost: String?
    /// Gerade gestartet, noch nicht da: das Symbol huepft (Apple-Dock).
    private(set) var launching: Set<String> = []
    /// Zaehler je Bundle-ID aus Apples Dock (`DockBadges`).
    private(set) var badges: [String: String] = [:]

    @ObservationIgnored private let live: Bool
    /// Welcher Dateimanager oben steht (Nexus > Anbieter); `nil` in Bildproben.
    @ObservationIgnored private let settings: ShellSettingsStore?
    @ObservationIgnored private var settingsObservation: Task<Void, Never>?
    /// Wer oben an Finders Platz steht (`ProviderFileManager.resolve`):
    /// laesst sich weder entfernen noch verschieben, wie Finder bei Apple.
    @ObservationIgnored private var fileManagerID = AppleDockPrefs.finder
    @ObservationIgnored private var badgeTimer: Timer?
    /// Ein Lesedurchgang laeuft noch; der naechste Takt faellt aus.
    @ObservationIgnored private var badgeReading = false
    /// Keine Leiste zu sehen (Vollbild): Zaehler nicht lesen. Setzt der
    /// Verwalter der Leisten wie bei CPU und Wetter.
    var badgesPaused = false {
        didSet {
            guard live, badgesPaused != oldValue else { return }
            if badgesPaused { stopBadgeTimer() } else { startBadgeTimer() }
        }
    }
    /// Alle 3 s: Apples Dock meldet Zaehler-Aenderungen nicht, und ein
    /// Lesedurchgang sind ein paar Bedienungshilfen-Aufrufe (~ms).
    private static let badgeInterval: TimeInterval = 3
    private static let dockDomain = "com.apple.dock" as CFString
    /// Symbole aus dem Dateisystem sind teuer; einmal geladen reicht.
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private let ownBundleID = Bundle.main.bundleIdentifier
    @ObservationIgnored private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "dock")

    init(settings: ShellSettingsStore) {
        live = true
        self.settings = settings
        frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        refresh()
        // Anderer Dateimanager in Nexus: gilt sofort. Liefert zuerst den
        // aktuellen Wert (ein Durchgang mehr, schadet nicht), danach jede
        // Aenderung; lebt so lange wie die Leiste.
        settingsObservation = Task { [weak self, settings] in
            for await _ in Observations({ settings.settings.providers.fileManager }) {
                self?.refresh()
            }
        }
        // Lebt so lange wie die Leiste und damit der Prozess.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.activated(id) }
        }
        startBadgeTimer()
    }

    /// Fuer die Bildprobe: feste Eintraege, liest und startet nichts.
    init(preview entries: [Entry], frontmost: String?, badges: [String: String] = [:]) {
        live = false
        settings = nil
        self.entries = entries
        self.frontmost = frontmost
        self.badges = badges
    }

    private func startBadgeTimer() {
        guard badgeTimer == nil else { return }
        pollBadges()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.badgeInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollBadges() }
        }
        timer.tolerance = 0.5
        badgeTimer = timer
    }

    private func stopBadgeTimer() {
        badgeTimer?.invalidate()
        badgeTimer = nil
    }

    /// Liest neben dem Hauptthread: haengt Apples Dock, warten die
    /// Bedienungshilfen-Aufrufe bis zum Timeout, und die Leiste soll dabei
    /// nicht stocken.
    private func pollBadges() {
        guard !badgeReading else { return }
        badgeReading = true
        Task { [weak self] in
            let next = await DockBadges.readOffMain()
            guard let self else { return }
            self.badgeReading = false
            if next != self.badges { self.badges = next }
        }
    }

    /// Apples Dock-Einstellung frisch lesen (Synchronize holt Aenderungen,
    /// die der Dock-Prozess seit dem letzten Lesen geschrieben hat) und neu
    /// zusammensetzen.
    func refresh() {
        guard live else { return }
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [Any] ?? []
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != ownBundleID
        }
        var running: [String: NSRunningApplication] = [:]
        for app in apps {
            if let id = app.bundleIdentifier, running[id] == nil { running[id] = app }
        }
        // Oben der Dateimanager aus Nexus > Anbieter, solange installiert,
        // sonst ForkLift oder Finder. Finder verschwindet nur, wenn ein
        // anderer ihn ersetzt (er laeuft immer und kaeme sonst unter
        // "laufend" wieder).
        let fileManager = ProviderFileManager.resolve(setting: settings?.settings.providers.fileManager) {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
        if fileManager != fileManagerID {
            // Das Ordner-Symbol haengt am Platz, nicht an der App: beide neu.
            icons[fileManagerID] = nil
            icons[fileManager] = nil
            fileManagerID = fileManager
        }
        let slots = DockLayout.slots(
            pinned: AppleDockPrefs.pinnedBundleIDs(tiles, fileManager: fileManager),
            running: apps.compactMap(\.bundleIdentifier),
            hidden: ProviderFileManager.hidden(for: fileManager),
            alwaysRunning: [fileManager]
        ) { id in
            running[id] != nil || NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
        }
        let next = slots.compactMap { slot -> Entry? in
            let app = running[slot.bundleID]
            guard let url = app?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: slot.bundleID)
            else { return nil }
            return Entry(
                bundleID: slot.bundleID,
                name: app?.localizedName ?? FileManager.default.displayName(atPath: url.path),
                icon: icon(for: slot.bundleID, app: app, url: url),
                pinned: slot.pinned,
                running: slot.running,
                hidden: app?.isHidden ?? false
            )
        }
        if next != entries { entries = next }
        // Fertig gestartet: nicht mehr huepfen.
        let started = launching.intersection(running.keys)
        if !started.isEmpty { launching.subtract(started) }
    }

    func runningApp(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// Klick auf ein Symbol, mit den Modifikatoren von Apples Dock
    /// (`DockClickAction`). Der Zustand (laeuft, vorne, Fenster) geht in die
    /// reine Entscheidung `DockClick.actions`, hier wird nur ausgefuehrt.
    func click(_ entry: Entry, modifiers: NSEvent.ModifierFlags) {
        guard live else { return }
        perform(entry, command: modifiers.contains(.command), option: modifiers.contains(.option))
    }

    /// Baut den Zustand fuer `entry`, laesst `DockClick` entscheiden und
    /// fuehrt die Aktionen der Reihe nach aus.
    private func perform(_ entry: Entry, command: Bool, option: Bool) {
        let app = runningApp(entry.bundleID)
        let windows = app.map { DockWindows.list(pid: $0.processIdentifier) } ?? []
        let visible = windows.filter { !$0.minimized }
        // Nur nicht minimierte Fenster koennen "hier" sein: welche davon
        // gerade auf dem Bildschirm liegen, sagt der aktuelle Space
        // (`onScreenWindowIDs`), nicht die Bedienungshilfen-Liste - die
        // kennt keine Spaces.
        let onScreen = app.map { DockWindows.onScreenWindowIDs(pid: $0.processIdentifier) } ?? []
        let onActiveSpace = visible.filter { $0.windowID.map(onScreen.contains) ?? false }
        // Fenster auf anderen Schreibtischen kennt die Bedienungshilfen-Liste
        // nicht (sie zeigt nur den aktuellen), deshalb aus der Fensterliste des
        // Systems: alle minus die hiesigen minus die abgelegten.
        let minimizedIDs = Set(windows.filter(\.minimized).compactMap(\.windowID))
        let elsewhere = app.map {
            DockWindows.allWindowIDs(pid: $0.processIdentifier, requireSpace: !$0.isHidden)
                .subtracting(onScreen)
                .subtracting(minimizedIDs)
                .count
        } ?? 0
        let previous = NSWorkspace.shared.frontmostApplication
        let frontmost = app != nil && app?.processIdentifier == previous?.processIdentifier
        // Nur nachsehen, wenn es ueberhaupt zur Frage kommt (eigener
        // Bildschirm-Aufruf): schon vorne, mit mindestens einem Fenster hier.
        // Beim Klick auf die schon vordere App nur blaettern, wenn wirklich
        // etwas im Weg liegt, nicht bei mehreren frei nebeneinander
        // liegenden Fenstern.
        let coveredWindowID: CGWindowID? = (frontmost && !onActiveSpace.isEmpty)
            ? app.flatMap { DockWindows.coveredWindowID(pid: $0.processIdentifier) }
            : nil
        let state = DockClickState(
            running: app != nil,
            launching: launching.contains(entry.bundleID),
            frontmost: frontmost,
            hidden: app?.isHidden ?? false,
            windowsOnActiveSpace: onActiveSpace.count,
            windowsElsewhere: elsewhere,
            minimizedWindows: windows.count(where: \.minimized),
            hasCoveredWindow: coveredWindowID != nil,
            command: command,
            option: option
        )
        let actions = DockClick.actions(for: state)
        for action in actions {
            switch action {
            case .launch:
                open(entry)
            case .unhide:
                _ = app?.unhide()
            case .activate:
                app?.activate()
            case .raiseWindowOnActiveSpace:
                // Das vorderste hiesige Fenster: es bringt die App gleich
                // mit nach vorne, kein zusaetzliches `.activate` noetig.
                if let app, let window = onActiveSpace.first {
                    DockWindows.raise(window, of: app)
                }
            case .raiseCoveredWindow:
                if let app, let coveredWindowID, let window = windows.first(where: { $0.windowID == coveredWindowID }) {
                    DockWindows.raise(window, of: app)
                }
            case .unminimizeLast:
                // Keine Zeitstempel ueber die Bedienungshilfen: das
                // vorderste minimierte Fenster in der Liste steht dem
                // "zuletzt abgelegten" am naechsten (war vor dem Minimieren
                // vorne).
                if let last = windows.first(where: \.minimized) {
                    AXUIElementSetAttributeValue(last.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }
            case .newWindow:
                if let app,
                   let command = DockAppCommands.commands(pid: app.processIdentifier)
                       .first(where: { $0.kind == .newItem }) {
                    DockAppCommands.press(command, of: app)
                }
            case .hidePrevious:
                if let previous, previous.bundleIdentifier != entry.bundleID, previous.bundleIdentifier != ownBundleID {
                    previous.hide()
                }
            case .reveal:
                reveal(entry)
            }
        }
    }

    /// Ist die App schon vorne und hat mehrere Fenster: das naechste nach
    /// vorne (`DockWindowCycle`). `false` = nichts gewechselt.
    private func cycleWindows(of entry: Entry) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        let isFront = front.bundleIdentifier == entry.bundleID
        // Fensterliste nur, wenn es ueberhaupt in Frage kommt (AX-Aufruf).
        let windows = isFront ? DockWindows.list(pid: front.processIdentifier).filter { !$0.minimized } : []
        guard let index = DockWindowCycle.indexToRaise(isFrontmost: isFront, visibleWindows: windows.count) else {
            return false
        }
        DockWindows.raise(windows[index], of: front)
        return true
    }

    /// Dateien auf das Symbol gezogen: mit dieser App oeffnen, wie im
    /// Apple-Dock. Startet sie dafuer, wenn noetig.
    func openFiles(_ urls: [URL], with entry: Entry) {
        let files = urls.filter(\.isFileURL)
        guard live, !files.isEmpty,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID)
        else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(files, withApplicationAt: app, configuration: configuration) { [log] _, error in
            if let error {
                log.error("Dock: Dateien nicht geoeffnet: \((error as NSError).code, privacy: .public)")
            }
        }
    }

    /// Scrollen auf dem Symbol: laeuft die App, nach vorne bzw. - ist sie
    /// schon vorne - ihr naechstes Fenster. Nicht laufende Apps startet
    /// Scrollen nicht (versehentlich beim Vorbeiwischen).
    func scroll(_ entry: Entry) {
        guard live, runningApp(entry.bundleID) != nil else { return }
        if !cycleWindows(of: entry) { perform(entry, command: false, option: false) }
    }

    // MARK: Anheften, Entfernen, Verschieben (schreibt Apples Dock-Liste)

    /// In Apples Dock angeheftet - nicht nur oben als Dateimanager.
    func isPinnedInDock(_ entry: Entry) -> Bool {
        entry.pinned && entry.bundleID != fileManagerID
    }

    /// Der Dateimanager oben steht fest, wie Finder bei Apple.
    func canPin(_ entry: Entry) -> Bool {
        entry.bundleID != fileManagerID
    }

    func togglePin(_ entry: Entry) {
        guard live, canPin(entry) else { return }
        if isPinnedInDock(entry) {
            writeTiles { AppleDockPrefs.removing(entry.bundleID, from: $0) }
        } else {
            place(entry.bundleID, onto: nil)
        }
    }

    /// Symbol `source` auf `target` gezogen: nimmt dessen Platz ein (nach
    /// unten gezogen dahinter, nach oben davor - wie beim Umsortieren im
    /// Apple-Dock). Eine nur laufende App wird dabei angeheftet. Auf den
    /// Dateimanager oben: an den Anfang; auf eine nur laufende App oder
    /// `nil`: ans Ende der angehefteten.
    func place(_ source: String, onto target: String?) {
        guard live, source != fileManagerID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source)
        else { return }
        let ids = entries.map(\.bundleID)
        let position: AppleDockPrefs.Position
        if let target, target == fileManagerID {
            position = .start
        } else if let target, let entry = entries.first(where: { $0.bundleID == target }), isPinnedInDock(entry) {
            let from = ids.firstIndex(of: source) ?? ids.count
            let to = ids.firstIndex(of: target) ?? ids.count
            position = from < to ? .after(target) : .before(target)
        } else {
            position = .end
        }
        let label = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        writeTiles {
            AppleDockPrefs.placing(source, at: position, in: $0) {
                AppleDockPrefs.tile(bundleID: source, url: url, label: label, guid: Int.random(in: 1...Int(Int32.max)))
            }
        }
    }

    /// Aendert "persistent-apps" in Apples Dock-Einstellung ueber
    /// cfprefsd (nicht an der Datei vorbei, sonst saehe die Leiste den alten
    /// Stand). Der ausgeblendete Dock selbst liest die Liste erst beim
    /// naechsten Start (Anmelden) neu; bis dahin zaehlt die Leiste.
    private func writeTiles(_ change: ([Any]) -> [Any]) {
        CFPreferencesAppSynchronize(Self.dockDomain)
        let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, Self.dockDomain) as? [Any] ?? []
        let next = change(tiles)
        CFPreferencesSetAppValue("persistent-apps" as CFString, next as NSArray as CFArray, Self.dockDomain)
        CFPreferencesAppSynchronize(Self.dockDomain)
        refresh()
    }

    /// "In <Dateimanager> zeigen": markiert, wenn der gewaehlte Dateimanager
    /// auch der Dateiviewer des Systems ist (NSFileViewer, nur gelesen);
    /// sonst oeffnet er den enthaltenden Ordner (`ProviderFileManager.reveal`).
    func reveal(_ entry: Entry) {
        guard live, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID) else { return }
        let viewer = UserDefaults.standard.string(forKey: "NSFileViewer")
        switch ProviderFileManager.reveal(fileManager: fileManagerID, systemFileViewer: viewer) {
        case .selectInFileViewer:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .openFolder(let id):
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                // Eben deinstalliert: lieber im Systemviewer als gar nicht.
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([url.deletingLastPathComponent()], withApplicationAt: app,
                                    configuration: configuration) { [log] _, error in
                if let error {
                    log.error("Dock: Ordner nicht gezeigt: \((error as NSError).code, privacy: .public)")
                }
            }
        }
    }

    /// Fuer "In … zeigen" im Dock-Menue: der Dateimanager oben.
    var fileManagerName: String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: fileManagerID) else { return "Finder" }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Wie ein Klick im Apple-Dock: laeuft sie, nach vorne (ohne Fenster
    /// macht die App ein neues auf), sonst starten - dann huepft das Symbol,
    /// bis sie da ist (hoechstens 15 s, falls der Start scheitert).
    private func open(_ entry: Entry) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID) else { return }
        if runningApp(entry.bundleID) == nil {
            launching.insert(entry.bundleID)
            let id = entry.bundleID
            Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.launching.remove(id) }
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [log] _, error in
            if let error {
                log.error("Dock: Start fehlgeschlagen: \((error as NSError).code, privacy: .public)")
            }
        }
    }

    private func activated(_ id: String?) {
        // Nexus holt den Launcher selbst nach vorne; dann gilt weiter die App davor.
        guard let id, id != ownBundleID, id != frontmost else { return }
        frontmost = id
    }

    private func icon(for id: String, app: NSRunningApplication?, url: URL) -> NSImage {
        if let cached = icons[id] { return cached }
        // Der Dateimanager oben steht fuer "den Dateimanager" und sieht
        // deshalb aus wie ein gewoehnlicher Ordner - welche App es auch ist,
        // ausser Finder mit seinem eigenen Gesicht. Nur hier in der Leiste,
        // die App selbst bleibt unangetastet (sonst bricht ihre Signatur und
        // das Selbst-Update).
        let icon = id == fileManagerID && id != AppleDockPrefs.finder
            ? DockIconArt.folder
            : app?.icon ?? NSWorkspace.shared.icon(forFile: url.path)
        icons[id] = icon
        return icon
    }
}

/// Eigenes Ordner-Symbol fuer den Dateimanager im Stil seiner App-Symbole.
///
/// Er hat den Symbolstil "Klar" (hell): macOS rendert App-Symbole dann als
/// graue Glas-Kachel mit hellem Motiv. Das allgemeine Ordner-Symbol
/// (`icon(for: .folder)`) bekommt diesen Stil nicht und war gelb - "passt 0 %
/// zu den restlichen" (14.09.). Deshalb nachgebaut: Werte aus der Bildprobe
/// der echten Symbole gemessen (Kachel Grau 0,62 oben bis 0,57 unten, Motiv
/// fast weiss), Kachel wie Apples App-Symbole 82 % der Flaeche mit 22,5 %
/// Eckenradius. Vektor, also in jeder Aufloesung scharf.
@MainActor
enum DockIconArt {
    static let folder: NSImage = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
        let side = rect.width * 0.82
        let tile = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        let shape = NSBezierPath(roundedRect: tile, xRadius: side * 0.225, yRadius: side * 0.225)
        NSGradient(starting: NSColor(white: 0.62, alpha: 1), ending: NSColor(white: 0.55, alpha: 1))?
            .draw(in: shape, angle: -90)
        // Feine helle Kante wie das Glas der echten Kacheln.
        NSColor(white: 1, alpha: 0.18).setStroke()
        shape.lineWidth = rect.width * 0.012
        shape.stroke()

        let config = NSImage.SymbolConfiguration(pointSize: side * 0.46, weight: .medium)
            .applying(.init(paletteColors: [NSColor(white: 0.97, alpha: 1)]))
        if let glyph = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let size = glyph.size
            glyph.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                  width: size.width, height: size.height))
        }
        return true
    }
}

/// Die Symbole untereinander, mittig zwischen Spaces und Uhr. Passen nicht
/// alle, laesst sich die Spalte scrollen (ohne Balken, wie das Apple-Dock
/// stattdessen verkleinern wuerde - bei 44 pt Breite waere das zu klein).
///
/// Nexus > Leiste > Dock: nur angeheftete zeigen, Symbolgroesse. Das filtert
/// nur die Ansicht - das Modell liest weiter alles.
struct SidebarDock: View {
    let model: SidebarDockModel
    var options = BarDockOptions()
    /// Vorschau in Nexus: kein Hover, kein Klick, kein Menue, kein Ziehen -
    /// dort soll nichts eine echte App starten, beenden oder anheften.
    @Environment(\.barPreview) private var preview
    @Environment(\.colorScheme) private var dockColorScheme
    private var dockStyle: ShellStyle { ShellTheme.style(dockColorScheme) }

    private var entries: [SidebarDockModel.Entry] {
        options.showRunning ? model.entries : model.entries.filter(\.pinned)
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            column
            ScrollView(.vertical, showsIndicators: false) {
                column.padding(.vertical, 8)
            }
            // Oben und unten weich ausblenden statt hart abschneiden
            // (Apple: Scroll-Kante statt Trennlinie).
            .mask {
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                            .init(color: .black, location: 0.96), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .frame(maxHeight: .infinity)
        .animation(SidebarMotion.spatial, value: entries.map(\.id))
    }

    private var column: some View {
        let entries = entries
        let split = entries.firstIndex { !$0.pinned }
        // Mit Theme: `--apollo-dock-spacing` zwischen den Symbolen,
        // `--apollo-dock-icon-size` fuer ihre Groesse.
        return VStack(spacing: dockStyle.dockSpacing(4)) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                // Strich zwischen angehefteten und nur laufenden, wie im Apple-Dock.
                if index == split, index > 0 {
                    Capsule()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 20, height: 2)
                        .padding(.vertical, 3)
                }
                SidebarDockItem(
                    entry: entry,
                    iconSize: dockStyle.dockIconSize(CGFloat(options.iconSize.points)),
                    interactive: !preview,
                    active: entry.bundleID == model.frontmost,
                    launching: model.launching.contains(entry.bundleID),
                    badge: model.badges[entry.bundleID],
                    onClick: { model.click(entry, modifiers: $0) },
                    onMenu: { DockMenu.show(for: entry, model: model, at: $0) },
                    onScroll: { model.scroll(entry) },
                    onDropFiles: { model.openFiles($0, with: entry) },
                    onDropApp: { model.place($0, onto: entry.bundleID) }
                )
            }
        }
        // Volle Leistenbreite: sonst liegt die Spalte in der ScrollView am
        // linken Rand, und die Laufend-Punkte (links ausserhalb des Symbols)
        // werden abgeschnitten - Bildprobe 14.09.
        .frame(maxWidth: .infinity)
    }
}

/// Ein App-Symbol: laufend mit Punkt am linken Rand (die Aussenseite, wie
/// beim Apple-Dock am Bildschirmrand), im Vordergrund leicht hinterlegt,
/// beim Ueberfahren wie die anderen Symbole der Leiste, gedrueckt dunkler.
/// Maus-Logik (Klick, Halten, Rechtsklick) in `DockMouseCatcher`.
private struct SidebarDockItem: View {
    let entry: SidebarDockModel.Entry
    /// Kantenlaenge des Symbols (Nexus); der Knopf bleibt 32 x 32.
    let iconSize: CGFloat
    /// Aus: nur Bild, ohne Maus-Ansichten (Vorschau in Nexus).
    let interactive: Bool
    let active: Bool
    let launching: Bool
    let badge: String?
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onMenu: (NSView) -> Void
    let onScroll: () -> Void
    let onDropFiles: ([URL]) -> Void
    let onDropApp: (String) -> Void
    @State private var hovering = false
    @State private var pressed = false
    /// Dateien werden gerade darueber gezogen: wie im Apple-Dock hervorheben.
    @State private var dropTarget = false
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        Image(nsImage: entry.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: iconSize, height: iconSize)
            .brightness(pressed || dropTarget ? -0.25 : 0)
            .opacity(entry.hidden ? 0.5 : 1)
            .modifier(DockBounce(active: launching))
            .frame(width: 32, height: 32)
            .background(Color.primary.opacity(hovering || dropTarget ? 0.14 : active ? 0.10 : 0), in: .rect(cornerRadius: 9))
            // Zaehler wie in Apples Dock: rote Kapsel oben rechts.
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(style.danger, in: .capsule)
                        .fixedSize()
                        .offset(x: 5, y: -3)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: badge)
            .overlay(alignment: .leading) {
                if entry.running {
                    Circle()
                        // Mit Theme: `--apollo-dock-indicator-color`.
                        .fill(style.paint(.dockIndicator, or: Color.primary.opacity(0.65)))
                        .frame(width: 4, height: 4)
                        .offset(x: -5)
                }
            }
            .overlay {
                if interactive {
                    DockMouseCatcher(
                        bundleID: entry.bundleID, dragImage: entry.icon,
                        onClick: onClick, onMenu: onMenu, onPress: { pressed = $0 },
                        onScroll: onScroll, onDropFiles: onDropFiles, onDropApp: onDropApp,
                        onDropTarget: { dropTarget = $0 }
                    )
                }
            }
            // Nicht `onHover`: die Leiste gehoert einer nie aktiven App.
            .background {
                if interactive { HoverTracker { hovering = $0 } }
            }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.15), value: active)
            .help(entry.name)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.running ? String(localized: "\(entry.name), läuft") : entry.name)
            .accessibilityAddTraits(.isButton)
    }
}

/// Huepfen beim Start wie im Apple-Dock - dort weg vom Bildschirmrand, hier
/// also nach rechts. Nur solange gestartet wird: der Phasen-Animator laeuft
/// sonst dauernd und kostet Rechenzeit. Hoch abbremsend, runter wie fallend.
private struct DockBounce: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.phaseAnimator([0.0, 10.0]) { view, offset in
                view.offset(x: offset)
            } animation: { offset in
                offset > 0 ? .easeOut(duration: 0.22) : .easeIn(duration: 0.22)
            }
        } else {
            content
        }
    }
}
