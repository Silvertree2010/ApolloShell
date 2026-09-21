import AppKit
import ApolloShellCore
import SwiftUI

/// The Nexus panel under the menu bar item: a glass window like the other
/// panels of the shell, not an NSMenu, so the settings can be cards with
/// switches and a line of explanation (Vorssaint's panel as the model).
///
/// Focus as with the bar's popouts (`StatusPopout`): the panel never becomes
/// the key window, the app in front keeps the keyboard. A click outside
/// closes it through mouse monitors, Esc through a Carbon hotkey that only
/// holds while the panel is open.
@MainActor
final class NexusPanel {
    static let maxHeight: CGFloat = 680
    private static let cornerRadius: CGFloat = 24
    /// Gap to the menu bar and to the screen edges.
    private static let margin: CGFloat = 6

    let model: NexusPanelModel
    /// The item's frame on screen; `nil`: open under the pointer instead.
    var anchor: () -> NSRect? = { nil }

    private var panel: ShellPanel?
    private var glass: NSGlassEffectView?
    private var panelLayer: CAGradientLayer?
    private var escapeKey: GlobalHotKey?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private(set) var isOpen = false
    private var heightObservation: Task<Void, Never>?
    /// Top edge and room on the screen of the current opening.
    private var top: CGFloat = 0
    private var room: CGFloat = maxHeight

    init(model: NexusPanelModel) {
        self.model = model
        model.close = { [weak self] in self?.close() }
        // A tab with more or fewer cards: the window grows or shrinks, the
        // top edge stays under the menu bar.
        heightObservation = Task { [weak self, model] in
            for await _ in Observations({ model.wantedHeight }) {
                self?.fitHeight()
            }
        }
    }

    deinit {
        heightObservation?.cancel()
    }

    private var height: CGFloat {
        // Before the first measurement: the most it may be.
        let wanted = model.pageHeight > 0 ? model.wantedHeight : Self.maxHeight
        return min(wanted, room, Self.maxHeight).rounded(.up)
    }

    private func fitHeight() {
        guard let panel, isOpen else { return }
        var frame = panel.frame
        let height = self.height
        guard abs(frame.height - height) > 0.5 else { return }
        frame.origin.y = top - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    func open() {
        let anchorFrame = anchor()
        let point = anchorFrame.map { NSPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        model.refresh()
        let panel = self.panel ?? makePanel()
        let visible = screen.visibleFrame
        room = visible.height - 2 * Self.margin
        top = visible.maxY - Self.margin
        let size = NSSize(width: NexusPanelView.width, height: height)
        let x = min(max(point.x - size.width / 2, visible.minX + Self.margin), visible.maxX - size.width - Self.margin)
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        panelLayer = ThemedGlass.apply(to: glass, fallbackRadius: Self.cornerRadius, previous: panelLayer)

        if !isOpen {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                panel.animator().alphaValue = 1
            }
            installMonitors()
            registerEscape()
        }
        isOpen = true
    }

    func close() {
        guard isOpen, let panel else { return }
        isOpen = false
        removeMonitors()
        escapeKey?.unregister()
        escapeKey = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isOpen else { return }
                panel.orderOut(nil)
            }
        })
    }

    private func makePanel() -> ShellPanel {
        let panel = ShellPanel(level: .popUpMenu, behavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle])
        let container = NSView(frame: NSRect(x: 0, y: 0, width: NexusPanelView.width, height: Self.maxHeight))
        container.autoresizingMask = [.width, .height]
        let glass = NSGlassEffectView(frame: container.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.cornerRadius = Self.cornerRadius
        let content = NSView(frame: container.bounds)
        content.autoresizingMask = [.width, .height]
        let hosting = FirstMouseHostingView(rootView: NexusPanelView(model: model).shellTheme())
        hosting.sizingOptions = []
        hosting.frame = content.bounds
        hosting.autoresizingMask = [.width, .height]
        content.addSubview(hosting)
        glass.contentView = content
        container.addSubview(glass)
        panel.contentView = container
        self.glass = glass
        self.panel = panel
        return panel
    }

    // MARK: - Esc and clicks outside

    private func registerEscape() {
        guard escapeKey == nil else { return }
        if case .success(let key) = GlobalHotKey.register(HotKey(keyCode: HotKeyKey.escape), action: { [weak self] in self?.close() }) {
            escapeKey = key
        }
    }

    private func installMonitors() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
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

    /// In the panel: stays open. On the menu bar item: its button toggles.
    /// In any other window of ours (bar, dashboard): close.
    private func localClick(_ event: NSEvent) {
        if event.window === panel { return }
        if let anchorFrame = anchor(), anchorFrame.contains(NSEvent.mouseLocation) { return }
        close()
    }
}
