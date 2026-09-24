import AppKit
import ApolloShellCore
import SwiftUI

/// The detail window of the status icons (Wi-Fi, Bluetooth, battery) in the
/// menu bar: below the bar, centred on the clicked icon
/// (`MenuBarPopoutPlacement`).
///
/// A panel of its own instead of the sidebar's bulge (`StatusPopout`): that
/// one grows out of the sidebar's glass and widens the sidebar's window,
/// which a strip across the whole screen can not do. The content is the
/// same `StatusPopoutContent` on the same model type, so both read and
/// switch alike. Opening, switching and closing follow the sidebar's
/// popout: same icon closes, another switches in place, a click elsewhere or
/// Esc closes.
@MainActor
final class MenuBarPopout {
    /// Handed to the bar's view through the environment: the status icons
    /// report their frames into it and call `onIconClick`.
    let model = StatusPopoutModel()

    /// An icon frame from the bar view (top = 0) in screen coordinates.
    var screenRect: (CGRect) -> NSRect? = { _ in nil }
    /// The bar's panel on the screen - the popout keeps off it.
    var barFrame: () -> NSRect? = { nil }
    /// This popout opens: the manager closes the one of any other bar.
    var onOpen: () -> Void = {}

    private var panel: ShellPanel?
    /// The clicked icon in screen coordinates.
    private var icon: NSRect?
    /// The content's size, reported by the view (the Bluetooth list grows
    /// once it is read).
    private var contentSize: CGSize = .zero
    private var escapeKey: GlobalHotKey?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var generation = 0

    init() {
        model.onIconClick = { [weak self] kind in self?.iconClicked(kind) }
        model.onOpenedSettings = { [weak self] in self?.close() }
    }

    var isOpen: Bool { model.isOpen }

    private func iconClicked(_ kind: StatusPopoutKind) {
        guard let rect = model.iconFrames[kind].flatMap(screenRect) else { return }
        icon = rect
        if model.isOpen {
            if model.shown == kind {
                close()
            } else {
                model.show(kind, anchorY: 0)
                contentSize = Self.measure(model: model, kind: kind)
                place()
            }
            return
        }
        open(kind)
    }

    private func open(_ kind: StatusPopoutKind) {
        generation += 1
        onOpen()
        let panel = self.panel ?? makePanel()
        model.show(kind, anchorY: 0)
        contentSize = Self.measure(model: model, kind: kind)
        place()
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        installMonitors()
        registerEscape()
    }

    func close() {
        guard model.isOpen else { return }
        generation += 1
        let current = generation
        model.hide()
        removeMonitors()
        escapeKey?.unregister()
        escapeKey = nil
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Opened again while fading: stays.
                guard let self, self.generation == current else { return }
                panel.orderOut(nil)
            }
        })
    }

    /// The first size before the view has reported one - a window of size
    /// zero would flash in the corner. Measured on a fresh view, as the
    /// panel's own reports nothing until it is laid out.
    private static func measure(model: StatusPopoutModel, kind: StatusPopoutKind) -> CGSize {
        NSHostingView(rootView: StatusPopoutContent(model: model, kind: kind).fixedSize().shellTheme()).fittingSize
    }

    fileprivate func contentSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != contentSize else { return }
        contentSize = size
        place()
    }

    private func place() {
        guard let panel, let icon, let bar = barFrame(), contentSize.width > 0 else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(bar) }?.frame ?? bar
        let frame = MenuBarPopoutPlacement.frame(icon: icon, bar: bar, size: contentSize, screen: screen)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    private func makePanel() -> ShellPanel {
        // Above the bars (a menu bar over Apple's stands at .statusBar), like
        // the edge drawers.
        let panel = ShellPanel(level: .popUpMenu,
                               behavior: [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary],
                               deferred: false)
        let hosting = FirstMouseHostingView(
            rootView: MenuBarPopoutView(model: model) { [weak self] in self?.contentSizeChanged($0) }.shellTheme()
        )
        // The panel's size is `place()`'s, from the reported content size.
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    // MARK: - Closing from outside

    /// Esc only while open - held all the time it would be missing in every
    /// app (the same rule as `StatusPopout`).
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

    /// In the popout: stays. On a status icon: its button decides (close or
    /// switch). Anywhere else in our own windows: close.
    private func localClick(_ event: NSEvent) {
        if let panel, event.window === panel { return }
        let point = NSEvent.mouseLocation
        let onIcon = model.iconFrames.values.contains { screenRect($0)?.contains(point) == true }
        if !onIcon { close() }
    }
}

/// The popout's content on the bar background, reporting its size so the
/// panel can follow it.
struct MenuBarPopoutView: View {
    let model: StatusPopoutModel
    let onSize: (CGSize) -> Void

    var body: some View {
        StatusPopoutContent(model: model, kind: model.shown)
            .fixedSize()
            .modifier(BarGlass(shape: RoundedRectangle(cornerRadius: StatusPopoutLayout.cornerRadius, style: .continuous)))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
