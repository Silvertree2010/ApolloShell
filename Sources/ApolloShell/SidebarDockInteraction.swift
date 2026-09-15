import AppKit
import ApolloShellCore
import ApplicationServices
import SwiftUI

extension NSPasteboard.PasteboardType {
    /// Bundle-ID eines Dock-Symbols, das in der Leiste verschoben wird.
    static let dockApp = NSPasteboard.PasteboardType(AppIdentity.scoped("dock-app"))
}

/// Maus auf einem Dock-Symbol, wie in Apples Dock: kurzer Klick loest aus
/// (mit Modifikatoren, beim Loslassen und nur ueber dem Symbol - Wegziehen
/// bricht ab), halten ab 0,5 s, Rechtsklick oder ⌃-Klick oeffnen das Menue,
/// Ziehen verschiebt das Symbol, Dateien darauf ziehen oeffnet sie mit der
/// App, Scrollen wechselt ihre Fenster.
///
/// Als AppKit-Ansicht statt SwiftUI-Button: SwiftUI kennt auf dem Mac weder
/// "halten" neben einem Klick noch den Rechtsklick sauber, das Menue braucht
/// eine Ansicht, an der es aufgeht, und Ziehen und Ablegen laeuft so an einer
/// Stelle statt verteilt auf zwei Welten.
struct DockMouseCatcher: NSViewRepresentable {
    let bundleID: String
    let dragImage: NSImage
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onMenu: (NSView) -> Void
    let onPress: (Bool) -> Void
    let onScroll: () -> Void
    let onDropFiles: ([URL]) -> Void
    let onDropApp: (String) -> Void
    let onDropTarget: (Bool) -> Void

    func makeNSView(context: Context) -> DockMouseView {
        let view = DockMouseView()
        update(view)
        return view
    }

    func updateNSView(_ view: DockMouseView, context: Context) {
        update(view)
    }

    private func update(_ view: DockMouseView) {
        view.bundleID = bundleID
        view.dragImage = dragImage
        view.onClick = onClick
        view.onMenu = onMenu
        view.onPress = onPress
        view.onScroll = onScroll
        view.onDropFiles = onDropFiles
        view.onDropApp = onDropApp
        view.onDropTarget = onDropTarget
    }
}

final class DockMouseView: NSView, NSDraggingSource {
    /// Apple-Dock: so lange halten, bis das Menue kommt.
    private static let holdDelay: TimeInterval = 0.5
    /// Ab so viel Bewegung ist es Ziehen statt Klicken.
    private static let dragThreshold: CGFloat = 4
    /// Trackpads liefern viele kleine Schritte: so viel aufsummieren, und
    /// hoechstens so oft wechseln, sonst rast man durch alle Fenster.
    private static let scrollStep: CGFloat = 30
    private static let scrollCooldown: TimeInterval = 0.3

    var bundleID = ""
    var dragImage: NSImage?
    var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onMenu: (NSView) -> Void = { _ in }
    var onPress: (Bool) -> Void = { _ in }
    var onScroll: () -> Void = {}
    var onDropFiles: ([URL]) -> Void = { _ in }
    var onDropApp: (String) -> Void = { _ in }
    var onDropTarget: (Bool) -> Void = { _ in }

    private var holdTimer: Timer?
    /// Menue kam durch Halten: das Loslassen danach ist kein Klick.
    private var menuShown = false
    private var downPoint: NSPoint?
    private var dragging = false
    private var scrolled: CGFloat = 0
    private var lastScrollStep = Date.distantPast

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .dockApp])
    }

    required init?(coder: NSCoder) {
        fatalError("nicht aus Nib")
    }

    /// Die Leiste gehoert einer App, die nie vorne ist; der erste Klick soll
    /// trotzdem gleich wirken.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Klicken und Halten

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onMenu(self)
            return
        }
        menuShown = false
        dragging = false
        downPoint = event.locationInWindow
        onPress(true)
        let timer = Timer(timeInterval: Self.holdDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.dragging else { return }
                self.menuShown = true
                self.onPress(false)
                self.onMenu(self)
            }
        }
        // .common: laeuft auch, waehrend AppKit die Maus verfolgt.
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, !dragging, !menuShown else { return }
        let point = event.locationInWindow
        guard hypot(point.x - start.x, point.y - start.y) > Self.dragThreshold else { return }
        dragging = true
        holdTimer?.invalidate()
        holdTimer = nil
        onPress(false)

        let item = NSPasteboardItem()
        item.setString(bundleID, forType: .dockApp)
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        dragItem.setDraggingFrame(bounds, contents: dragImage)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        holdTimer?.invalidate()
        holdTimer = nil
        downPoint = nil
        if dragging {
            dragging = false
            return
        }
        guard !menuShown else { return }
        onPress(false)
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick(event.modifierFlags)
    }

    override func rightMouseDown(with event: NSEvent) {
        onMenu(self)
    }

    // MARK: Ziehen (Quelle)

    /// Nur innerhalb der Leiste verschieben; ausserhalb abgelegt passiert
    /// nichts (kein "Wegziehen zum Entfernen" - dafuer gibt es das Menue).
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    // MARK: Ablegen (Ziel)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = operation(for: sender)
        onDropTarget(operation != [])
        return operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        operation(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDropTarget(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDropTarget(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDropTarget(false)
        let pasteboard = sender.draggingPasteboard
        if let id = pasteboard.string(forType: .dockApp) {
            guard id != bundleID else { return false }
            onDropApp(id)
            return true
        }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDropFiles(urls)
        return true
    }

    private func operation(for info: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = info.draggingPasteboard
        if let id = pasteboard.string(forType: .dockApp) {
            return id == bundleID ? [] : .move
        }
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }

    // MARK: Scrollen

    override func scrollWheel(with event: NSEvent) {
        // Laeuft die Spalte gerade als Scrollliste (zu viele Apps), gehoert
        // das Scrollen ihr - sonst liesse sie sich ueber den Symbolen nicht
        // mehr bewegen.
        if let scrollView = enclosingScrollView, let document = scrollView.documentView,
           document.frame.height > scrollView.contentView.bounds.height + 1 {
            super.scrollWheel(with: event)
            return
        }
        if event.phase == .began { scrolled = 0 }
        scrolled += abs(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 1 : 10)
        guard scrolled >= Self.scrollStep, Date().timeIntervalSince(lastScrollStep) > Self.scrollCooldown else { return }
        scrolled = 0
        lastScrollStep = Date()
        onScroll()
    }
}

/// Das Menue eines Dock-Symbols, aufgebaut wie Apples Dock-Menue, damit
/// die Eintraege dort stehen, wo man sie erwartet:
///
///     Fenster (aller Schreibtische)
///     ─
///     Befehle der App (Neues Fenster, Neues privates Fenster …)
///     ─
///     Optionen ▸ Im Dock behalten ✓ · In <Dateimanager> zeigen
///     Alle Fenster einblenden
///     ─
///     Ausblenden / Einblenden
///     Beenden (⌥: Sofort beenden)
///
/// Beim Oeffnen gebaut, damit Fensterliste, Befehle und Zustand stimmen.
@MainActor
enum DockMenu {
    static func show(for entry: SidebarDockModel.Entry, model: SidebarDockModel, at view: NSView) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let app = model.runningApp(entry.bundleID)

        if let app {
            // Alle Schreibtische: vorher nur der aktuelle, Fenster auf
            // anderen Schreibtischen fehlten dann im Menue.
            let windows = DockWindows.list(pid: app.processIdentifier, allSpaces: true)
            for window in windows {
                let item = ClosureMenuItem(window.title.isEmpty ? entry.name : window.title) {
                    DockWindows.raise(window, of: app)
                }
                if window.minimized { item.image = NSImage(systemSymbolName: "minus.circle", accessibilityDescription: String(localized: "Im Dock")) }
                menu.addItem(item)
            }
            if !windows.isEmpty { menu.addItem(.separator()) }

            let commands = DockAppCommands.newItems(pid: app.processIdentifier)
            for command in commands {
                menu.addItem(ClosureMenuItem(command.title) { DockAppCommands.press(command, of: app) })
            }
            if !commands.isEmpty { menu.addItem(.separator()) }
        } else {
            menu.addItem(ClosureMenuItem(String(localized: "Öffnen")) { model.click(entry, modifiers: []) })
            menu.addItem(.separator())
        }

        let options = NSMenuItem(title: String(localized: "Optionen"), action: nil, keyEquivalent: "")
        let optionsMenu = NSMenu()
        optionsMenu.autoenablesItems = false
        if model.canPin(entry) {
            let keep = ClosureMenuItem(String(localized: "Im Dock behalten")) { model.togglePin(entry) }
            keep.state = model.isPinnedInDock(entry) ? .on : .off
            optionsMenu.addItem(keep)
        }
        optionsMenu.addItem(ClosureMenuItem(String(localized: "In \(model.fileManagerName) zeigen")) { model.reveal(entry) })
        options.submenu = optionsMenu
        menu.addItem(options)

        if let app {
            menu.addItem(ClosureMenuItem(String(localized: "Alle Fenster einblenden")) { SpaceSwitcher.showAppWindows(of: app) })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(app.isHidden ? String(localized: "Einblenden") : String(localized: "Ausblenden")) {
                // Ergebnis egal: scheitert es, bleibt die App, wie sie war.
                _ = app.isHidden ? app.unhide() : app.hide()
            })
            menu.addItem(ClosureMenuItem(String(localized: "Beenden")) { app.terminate() })
            // Wie bei Apple: mit gedrueckter ⌥-Taste wird daraus "Sofort beenden".
            let force = ClosureMenuItem(String(localized: "Sofort beenden")) { app.forceTerminate() }
            force.isAlternate = true
            force.keyEquivalentModifierMask = .option
            menu.addItem(force)
        }

        // Rechts neben dem Symbol, oben buendig - die Leiste liegt links.
        let top = view.isFlipped ? view.bounds.minY : view.bounds.maxY
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.maxX + 6, y: top), in: view)
    }
}

/// Fenster einer App ueber die Bedienungshilfen (die Freigabe hat die App
/// fuer die Fensterwache). Ohne Freigabe: leere Liste, das Menue hat dann
/// nur die Befehle.
enum DockWindows {
    struct Window {
        let title: String
        let minimized: Bool
        let element: AXUIElement
    }

    /// `allSpaces`: auch Fenster auf anderen Schreibtischen (fuers Menue).
    /// Ohne: nur der aktuelle, vorne nach hinten sortiert (fuers Durchschalten).
    @MainActor
    static func list(pid: pid_t, allSpaces: Bool = false) -> [Window] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        // Haengt die App, soll das Menue nicht mit ihr haengen.
        AXUIElementSetMessagingTimeout(app, 0.3)
        var elements = DockAX.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        if allSpaces {
            for element in RemoteWindows.all(pid: pid) where !elements.contains(where: { CFEqual($0, element) }) {
                elements.append(element)
            }
        }
        return elements.compactMap { element in
            // Nur echte Fenster, keine Paletten/Blaetter.
            guard DockAX.string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole as String else { return nil }
            return Window(title: DockAX.string(element, kAXTitleAttribute) ?? "",
                          minimized: (DockAX.value(element, kAXMinimizedAttribute) as? NSNumber)?.boolValue ?? false,
                          element: element)
        }
    }

    /// Wie ein Klick auf das Fenster im Dock-Menue: aus dem Dock holen, falls
    /// minimiert, zum Hauptfenster machen und nach oben, dann die App nach
    /// vorne. In dieser Reihenfolge wechselt macOS dabei auf den
    /// Schreibtisch dieses Fensters (vorne ist dann genau dieses).
    @MainActor
    static func raise(_ window: Window, of app: NSRunningApplication) {
        if window.minimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        app.activate()
    }
}

/// Fenster auf anderen Schreibtischen. `kAXWindowsAttribute` liefert nur die
/// des aktuellen. Der Weg von AltTab: Bedienungshilfen-Elemente ueber ihre
/// Nummer direkt erzeugen (private Funktion `_AXUIElementCreateWithRemoteToken`
/// in HIServices, per dlsym) und die Nummern 0 bis 999 durchprobieren.
/// Gemessen 14.09.: kitty 3 Fenster statt 2 in 46 ms, Vivaldi 16 ms - kurz
/// genug, um es beim Oeffnen des Menues zu tun.
enum RemoteWindows {
    private typealias Create = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    /// RTLD_DEFAULT ist auf macOS der Zeiger -2.
    private static let create: Create? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementCreateWithRemoteToken") else { return nil }
        return unsafeBitCast(symbol, to: Create.self)
    }()
    private static let maxElementID: UInt64 = 1000

    @MainActor
    static func all(pid: pid_t) -> [AXUIElement] {
        guard let create else { return [] }
        // Aufbau des Tokens (AltTab): pid, 0, "coco", Elementnummer.
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
        var windows: [AXUIElement] = []
        for elementID in 0..<maxElementID {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let element = create(token as CFData)?.takeRetainedValue(),
                  DockAX.string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole as String
            else { continue }
            windows.append(element)
        }
        return windows
    }
}

/// Befehle der App aus ihrer Menueleiste, siehe `DockCommandFilter`.
enum DockAppCommands {
    struct Command {
        let title: String
        let element: AXUIElement
    }

    @MainActor
    static func newItems(pid: pid_t) -> [Command] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let barValue = DockAX.value(app, kAXMenuBarAttribute),
              CFGetTypeID(barValue) == AXUIElementGetTypeID()
        else { return [] }
        let bar = unsafeDowncast(barValue, to: AXUIElement.self)
        // 0 = Apple-Menue, 1 = App-Menue, 2 = File/Ablage (kitty: Shell).
        let menus = DockAX.value(bar, kAXChildrenAttribute) as? [AXUIElement] ?? []
        guard menus.count > 2,
              let menu = (DockAX.value(menus[2], kAXChildrenAttribute) as? [AXUIElement])?.first
        else { return [] }
        let items = DockAX.value(menu, kAXChildrenAttribute) as? [AXUIElement] ?? []
        return items.compactMap { item in
            guard let title = DockAX.string(item, kAXTitleAttribute), DockCommandFilter.isNewCommand(title),
                  (DockAX.value(item, kAXEnabledAttribute) as? NSNumber)?.boolValue ?? false
            else { return nil }
            return Command(title: title, element: item)
        }
    }

    /// App nach vorne, dann den Menuepunkt auswaehlen - wie ueber ihre
    /// Menueleiste, das neue Fenster kommt also auf dem aktuellen Schreibtisch.
    @MainActor
    static func press(_ command: Command, of app: NSRunningApplication) {
        app.activate()
        AXUIElementPerformAction(command.element, kAXPressAction as CFString)
    }
}

/// Zaehler (Ungelesen usw.) aus Apples Dock: der ist ausgeblendet, fuehrt
/// sie aber weiter und zeigt sie den Bedienungshilfen als AXStatusLabel je
/// Symbol. Gemessen 14.09.: eine AXList mit AXApplicationDockItem-Kindern,
/// jedes mit Titel und AXURL auf die App.
enum DockBadges {
    @MainActor
    static func read() -> [String: String] {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [:] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.3)
        let lists = DockAX.value(app, kAXChildrenAttribute) as? [AXUIElement] ?? []
        guard let list = lists.first(where: { DockAX.string($0, kAXRoleAttribute) == kAXListRole as String }) else { return [:] }
        var badges: [String: String] = [:]
        for item in DockAX.value(list, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            guard let label = DockAX.string(item, "AXStatusLabel"), !label.isEmpty,
                  let url = DockAX.value(item, kAXURLAttribute) as? URL,
                  let id = Bundle(url: url)?.bundleIdentifier
            else { continue }
            badges[id] = label
        }
        return badges
    }
}

/// Die zwei Lesezugriffe, die Menue und Zaehler brauchen.
private enum DockAX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }
}

/// Menuepunkt mit Block statt Ziel/Aktion.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("nicht aus Nib")
    }

    @objc private func run() {
        handler()
    }
}
