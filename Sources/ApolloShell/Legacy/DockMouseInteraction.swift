import AppKit
import ApolloShellCore
import ApplicationServices
import CoreGraphics
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
