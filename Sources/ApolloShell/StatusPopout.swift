import AppKit
import ApolloShellCore
import SwiftUI

/// The detail window for Wi-Fi, Bluetooth and battery that grows out of the
/// bar (Caelestia: modules/bar/popouts).
///
/// The bar and the popout are a single glass area: the popout lives in the
/// window of the bar, in the same `GlassEffectContainer` (`SidebarRoot`), and
/// merges with it there. A window of its own next to it would not work - glass
/// out of two windows stays two areas with an edge between them.
///
/// On opening, the bar window becomes wider (`setExpanded`). The new room is
/// transparent, so nothing jumps. Then the glass grows out in SwiftUI
/// (`StatusPopoutStage`). After the closing motion the window becomes as
/// narrow as the bar again.
///
/// Focus: the window never becomes the key window, and the user's app keeps
/// the keyboard. So clicks outside close it through mouse monitors (the mouse
/// needs no permission) and Esc through a Carbon hotkey that only holds while
/// the popout is open - as with a menu, Esc then goes to the popout and not to
/// the app below.
@MainActor
final class StatusPopout {
    let model = StatusPopoutModel()

    /// Works out a symbol frame from the bar view (top = 0) into screen
    /// coordinates; set by the bar the view belongs to.
    var screenRect: (CGRect) -> NSRect? = { _ in nil }
    /// The window of the bar the popout lies in.
    weak var hostWindow: NSWindow?
    /// Make the bar window wider (`true`) or narrow again.
    var setExpanded: (Bool) -> Void = { _ in }
    /// This popout is opening. The manager of the bars then closes a popout
    /// that still stands open on another screen - only ever one is open.
    /// es ist immer nur eines offen.
    var onOpen: () -> Void = {}

    /// The width of the bar window with the popout open: the bar, the widest
    /// popout and room for the overshoot of the curve (~1.5 %).
    static var expandedWidth: CGFloat {
        Sidebar.width + StatusPopoutKind.allCases.map(StatusPopoutContent.width).max()! + 24
    }

    /// Esc while the popout is open. Every registration gets an id of its own
    /// in `GlobalHotKey` - with several bars the press lands at the open popout
    /// that way, not at the one that was built last.
    private var escapeKey: GlobalHotKey?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var generation = 0

    init() {
        model.onIconClick = { [weak self] kind in self?.iconClicked(kind) }
        model.onOpenedSettings = { [weak self] in self?.close() }
    }

    var isOpen: Bool { model.isOpen }

    // MARK: - Clicks on the status symbols

    /// The same symbol: close. Another symbol with the popout open: switch the
    /// content in place. Otherwise: open.
    private func iconClicked(_ kind: StatusPopoutKind) {
        // The symbol and the stage lie in the same view, top = 0: the centre
        // of the symbol is the anchor straight away.
        guard let anchor = model.iconFrames[kind]?.midY else { return }
        if model.isOpen {
            if model.shown == kind {
                close()
            } else {
                withAnimation(StatusPopoutMotion.spatial) { model.show(kind, anchorY: anchor) }
            }
            return
        }
        open(kind, anchorY: anchor)
    }

    private func open(_ kind: StatusPopoutKind, anchorY: CGFloat) {
        generation += 1
        // First: an open popout on another bar closes before this one makes
        // its window wider.
        onOpen()
        setExpanded(true)
        // A seed without motion at the clicked symbol, then grow out.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { model.prepare(kind, anchorY: anchorY) }
        withAnimation(StatusPopoutMotion.spatial) { model.show(kind, anchorY: anchorY) }
        installMonitors()
        registerEscape()
    }

    func close() {
        guard model.isOpen else { return }
        generation += 1
        let current = generation
        withAnimation(StatusPopoutMotion.spatial) { model.hide() }
        removeMonitors()
        escapeKey?.unregister()
        escapeKey = nil
        // Narrow only after the closing motion; if one opens again before that, it stays wide.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.generation == current else { return }
            self.setExpanded(false)
        }
    }

    /// Esc belongs to the popout only while it is open - taken permanently, it
    /// would be missing in every app. If another app has taken Esc globally
    /// already, a click beside it and the symbol still close it.
    private func registerEscape() {
        guard escapeKey == nil else { return }
        if case .success(let key) = GlobalHotKey.register(HotKey(keyCode: HotKeyKey.escape), action: { [weak self] in self?.close() }) {
            escapeKey = key
        }
    }

    // MARK: - Clicks outside

    private func installMonitors() {
        guard globalMonitor == nil else { return }
        // Clicks into other apps: always outside.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        // Clicks into our own windows (bar, dashboard, ...). The global monitor
        // does not see those. The event always goes on.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.localClick(event) }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func localClick(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        if let window = hostWindow, event.window === window {
            // In the glass of the popout: it stays open. `panelFrame` counts
            // from the right bar edge, top = 0.
            let frame = window.frame
            let inStage = CGPoint(x: point.x - frame.minX - Sidebar.width, y: frame.maxY - point.y)
            if model.panelFrame.contains(inStage) { return }
        }
        // On a status symbol: its button takes care of that (close or switch).
        // Otherwise, in the transparent part of the wide window too: close.
        let onIcon = model.iconFrames.values.contains { screenRect($0)?.contains(point) == true }
        if !onIcon { close() }
    }
}
