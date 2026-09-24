import AppKit
import ColorSync
import ApolloShellCore

/// Ein angeschlossener Bildschirm, wie ihn die Shell benutzt: die
/// Beschreibung fuer die Auswahl (ApolloShellCore/ScreenSelection), das
/// NSScreen dazu und die Display-Kennung.
///
/// Zwei Schluessel, die man nicht verwechseln darf:
/// - `info.key` (Name plus Aufloesung) merkt sich eine EINSTELLUNG einen
///   Bildschirm ueber das Abstecken hinweg. Zwei baugleiche Bildschirme
///   haben denselben.
/// - `displayID` sagt, welcher Bildschirm JETZT gemeint ist. Eindeutig,
///   aber macOS vergibt sie beim Anstecken neu - nichts, was man in eine
///   Datei schreibt.
///
/// Die Fenster der Shell liegen deshalb nach `displayID` im Verzeichnis, die
/// Einstellung spricht ueber `info.key`.
struct ShellScreen: Identifiable {
    let displayID: CGDirectDisplayID
    /// Frisch bei jedem Durchgang geholt: ein NSScreen von vorhin kann nach
    /// einem Umstecken veraltete Masse melden.
    let screen: NSScreen
    let info: ScreenInfo

    var id: CGDirectDisplayID { displayID }
    var frame: NSRect { screen.frame }
    var visibleFrame: NSRect { screen.visibleFrame }
}

/// Die Bildschirme von AppKit holen und die Auswahl aus ApolloShellCore
/// darauf anwenden.
@MainActor
enum ShellScreens {
    /// Alle angeschlossenen Bildschirme, Hauptbildschirm (der mit der
    /// Menueleiste) zuerst - das ist die Reihenfolge von `NSScreen.screens`.
    ///
    /// Leer, wenn gerade keiner da ist (Kabel mitten im Umstecken): die
    /// Aufrufer lassen dann stehen, was steht.
    static func current() -> [ShellScreen] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        return screens.compactMap { screen in
            guard let id = displayID(of: screen) else { return nil }
            return ShellScreen(
                displayID: id,
                screen: screen,
                info: ScreenInfo(name: screen.localizedName, frame: screen.frame, isPrimary: screen === primary)
            )
        }
    }

    /// UUID eines Bildschirms, so wie SkyLight ihn in seiner Space-Liste
    /// fuehrt ("Display Identifier").
    static func uuid(of id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// Die Bildschirme, auf denen die Leiste (und mit ihr die
    /// Schreibtisch-Uhr und der freigehaltene Streifen) stehen soll.
    static func targets(for choice: ScreenChoice, among all: [ShellScreen] = current()) -> [ShellScreen] {
        let chosen = ScreenSelection.targets(among: all.map(\.info), choice: choice)
        // Ueber die Stelle in der Liste zurueckrechnen, nicht ueber den
        // Schluessel: zwei baugleiche Bildschirme haben denselben Schluessel,
        // und in Spiegelung sogar denselben Rahmen.
        var remaining = all
        var result: [ShellScreen] = []
        for info in chosen {
            guard let index = remaining.firstIndex(where: { $0.info == info }) else { continue }
            result.append(remaining.remove(at: index))
        }
        return result
    }

    /// Der Bildschirm unter einem Punkt in Bildschirmkoordinaten.
    static func at(_ point: NSPoint, among all: [ShellScreen] = current()) -> ShellScreen? {
        guard let info = ScreenSelection.screen(at: point, among: all.map(\.info)) else { return nil }
        return all.first { $0.info == info } ?? all.first
    }

    /// Der Bildschirm, auf dem der Zeiger gerade steht. Dort gehen Launcher,
    /// Dashboard, Utilities, Sitzungsmenue und Kurzmeldungen auf.
    static func underPointer(among all: [ShellScreen] = current()) -> ShellScreen? {
        at(NSEvent.mouseLocation, among: all)
    }

    /// Meldet jede Aenderung an den Bildschirmen: angesteckt, abgezogen,
    /// andere Aufloesung oder Anordnung. Der Beobachter lebt so lange wie der
    /// Prozess; wer ihn anlegt, haelt sich darin deshalb nur schwach.
    static func onChange(_ handler: @escaping @MainActor () -> Void) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    /// `NSScreenNumber` aus der Geraetebeschreibung ist die
    /// CGDirectDisplayID. Fehlt sie (kommt bei einem Bildschirm, der gerade
    /// verschwindet, vor), zaehlt der Bildschirm nicht mit.
    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// Ein Eintrag je Bildschirm, nach Display-Kennung: anlegen, auffrischen,
/// abraeumen - so, wie die Einstellung und die angeschlossenen Bildschirme
/// es gerade verlangen. Leiste und Schreibtisch-Uhr verteilen sich so.
@MainActor
struct ScreenSlots<Item> {
    private(set) var items: [CGDirectDisplayID: Item] = [:]

    /// Neu verteilen. `make` legt fuer einen neuen Bildschirm an, `update`
    /// laeuft danach fuer JEDEN gewuenschten (neu oder schon da), `remove`
    /// fuer jeden, der weg oder abgewaehlt ist.
    ///
    /// Ohne Bildschirme (Kabel mitten im Umstecken, `NSScreen.screens` leer)
    /// bleibt alles stehen, statt abgerissen und gleich wieder aufgebaut zu
    /// werden: dann `nil`. Kommen sie zurueck, meldet sich `onChange`.
    /// Sonst die Bildschirme, auf denen jetzt ein Eintrag steht.
    @discardableResult
    mutating func distribute(on choice: ScreenChoice,
                             make: (ShellScreen) -> Item,
                             update: (Item, ShellScreen) -> Void,
                             remove: (Item) -> Void) -> [ShellScreen]? {
        let all = ShellScreens.current()
        guard !all.isEmpty else { return nil }
        let wanted = ShellScreens.targets(for: choice, among: all)
        let keep = Set(wanted.map(\.displayID))
        for (id, item) in items where !keep.contains(id) {
            remove(item)
            items[id] = nil
        }
        for screen in wanted {
            let item = items[screen.displayID] ?? make(screen)
            items[screen.displayID] = item
            update(item, screen)
        }
        return wanted
    }

    /// Alles abraeumen (z. B. ausgeschaltet).
    mutating func removeAll(_ remove: (Item) -> Void) {
        for item in items.values { remove(item) }
        items = [:]
    }
}
