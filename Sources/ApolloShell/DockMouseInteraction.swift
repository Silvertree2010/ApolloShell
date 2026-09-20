import AppKit
import ApolloShellCore
import ApplicationServices
import CoreGraphics
import SwiftUI

extension NSPasteboard.PasteboardType {
    /// The bundle ID of a Dock symbol that is being moved in the bar.
    static let dockApp = NSPasteboard.PasteboardType(AppIdentity.scoped("dock-app"))
}

/// The mouse on a Dock symbol, as in Apple's Dock: a short click sets it off
/// (with modifiers, on release and only over the symbol - dragging away
/// cancels), holding from 0.5 s on, a right click or a ⌃ click opens the menu,
/// dragging moves the symbol, dragging files onto it opens them with the app,
/// and scrolling switches its windows.
///
/// As an AppKit view instead of a SwiftUI button: on the Mac, SwiftUI knows
/// neither "holding" next to a click nor the right click cleanly, the menu
/// needs a view to open at, and dragging and dropping runs in one place that
/// way instead of being spread over two worlds.
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
    /// The Apple Dock: hold this long until the menu comes.
    private static let holdDelay: TimeInterval = 0.5
    /// From this much movement on it is dragging instead of clicking.
    private static let dragThreshold: CGFloat = 4
    /// Trackpads deliver many small steps: sum up this much, and switch at most
    /// this often, otherwise one races through all the windows.
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
    /// The menu came through holding: the release afterwards is no click.
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

    /// The bar belongs to an app that is never at the front; the first click
    /// should take effect right away all the same.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Clicking and holding

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
        // .common: runs while AppKit tracks the mouse too.
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

    // MARK: Dragging (the source)

    /// Only moving within the bar; dropped outside, nothing happens (no
    /// "drag away to remove" - the menu is there for that).
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    // MARK: Dropping (the target)

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

    // MARK: Scrolling

    override func scrollWheel(with event: NSEvent) {
        // When the column runs as a scrolling list right now (too many apps),
        // the scrolling belongs to it - otherwise it could no longer be moved
        // over the symbols.
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
