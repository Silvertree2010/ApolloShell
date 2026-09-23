import ApolloShellCore
import ApolloWM
import AppKit
import SwiftUI

/// The tab bars of the TWM's tab groups: one glass strip above each group's
/// window with a tab per window (icon and title), x to close a tab's window
/// and + for a new window in the group. Follows `TilingEngine.onTabBarsChanged`,
/// so a bar glides along with its window.
@MainActor
final class TWMTabBars {
    private let engine: TilingEngine
    /// One panel per group, keyed by the group's first window.
    private var panels: [CGWindowID: TabBarPanel] = [:]

    init(engine: TilingEngine) {
        self.engine = engine
        engine.onTabBarsChanged = { [weak self] bars in self?.show(bars) }
        show(engine.tabBars())
    }

    func close() {
        picker.close()
        engine.onTabBarsChanged = nil
        for panel in panels.values { panel.orderOut(nil) }
        panels = [:]
    }

    private func show(_ bars: [TilingEngine.TabBar]) {
        var kept: Set<CGWindowID> = []
        for bar in bars {
            guard let key = bar.tabs.first?.windowID else { continue }
            kept.insert(key)
            let panel = panels[key] ?? TabBarPanel(actions: actions)
            panels[key] = panel
            panel.update(bar)
        }
        for (key, panel) in panels where !kept.contains(key) {
            panel.orderOut(nil)
            panels[key] = nil
        }
    }

    private var actions: TabBarActions {
        TabBarActions(
            select: { [weak self] id in self?.engine.activateTab(id) },
            close: { [weak self] id in self?.engine.windows[id]?.close() },
            add: { [weak self] shown, button in self?.showNewTabMenu(for: shown, from: button) },
            reorder: { [weak self] id, place in self?.engine.moveTab(id, to: place) },
            cycle: { [weak self] forward in
                guard let self, let shown = self.engine.tabBars().first?.active else { return }
                self.engine.cycleTab(from: shown, forward: forward)
            },
            detach: { [weak self] id in self?.engine.toggleGroup(id) }
        )
    }

    private let picker = TWMAppPicker()

    /// The + : a search panel with open apps first, then every installed
    /// one. The chosen app's new window joins this group.
    private func showNewTabMenu(for shown: CGWindowID, from view: NSView) {
        picker.show(below: view) { [weak self] choice in
            switch choice {
            case .running(let app): self?.openWindow(of: app, joining: shown)
            case .installed(let url): self?.launch(url, joining: shown)
            }
        }
    }

    /// A running app: its "New Window" (plain ⌘N) from its menu bar, the way
    /// the Dock menu does it; apps without one are just brought forward.
    private func openWindow(of app: NSRunningApplication, joining shown: CGWindowID) {
        engine.routeNextWindow(of: app.processIdentifier, intoGroupWith: shown)
        if let command = DockAppCommands.commands(pid: app.processIdentifier).first(where: \.isNewWindow) {
            DockAppCommands.press(command, of: app)
        } else {
            app.activate()
        }
    }

    /// An app that is not running: its first window joins the group.
    private func launch(_ url: URL, joining shown: CGWindowID) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, _ in
            guard let pid = app?.processIdentifier else { return }
            Task { @MainActor [weak self] in
                self?.engine.routeNextWindow(of: pid, intoGroupWith: shown)
            }
        }
    }
}

struct TabBarActions {
    let select: (CGWindowID) -> Void
    let close: (CGWindowID) -> Void
    let add: (CGWindowID, NSView) -> Void
    /// A tab was dragged to another place on the bar.
    let reorder: (CGWindowID, Int) -> Void
    /// Scrolling over the bar walks the tabs.
    let cycle: (Bool) -> Void
    /// A tab dragged off the bar gets a tile of its own again.
    let detach: (CGWindowID) -> Void
}

/// One tab bar: a normal-level glass panel (the tile below belongs to its
/// window, so nothing else overlaps it) that never takes focus.
@MainActor
private final class TabBarPanel: ShellPanel {
    private let model = TabBarModel()
    private let glass: NSGlassEffectView
    private var glassLayer: CAGradientLayer?
    private var themed = false

    init(actions: TabBarActions) {
        glass = NSGlassEffectView()
        super.init(level: .normal, behavior: [.ignoresCycle, .transient], mayLeaveScreen: true)
        model.actions = actions
        let content = ScrollCatchingView()
        content.onScroll = { [weak model] forward in model?.actions?.cycle(forward) }
        let hosting = FirstMouseHostingView(rootView: TabBarView(model: model).shellTheme())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: content.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        glass.contentView = content
        contentView = glass
    }

    /// Called on every animation frame while the group glides: only what
    /// changed is touched. Setting the model redraws SwiftUI, a synchronous
    /// display and a re-order each cost a window-server round trip.
    func update(_ bar: TilingEngine.TabBar) {
        if model.tabs != bar.tabs { model.tabs = bar.tabs }
        if model.active != bar.active { model.active = bar.active }
        let height = NSScreen.screens.first?.frame.height ?? 0
        // The bar sits in the tile's top strip, a little inset.
        let frame = bar.frame.insetBy(dx: 0, dy: 2)
        let rect = NSRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
        if rect != self.frame { setFrame(rect, display: false) }
        if !themed {
            glassLayer = ThemedGlass.apply(to: glass, fallbackRadius: 10, previous: glassLayer)
            themed = true
        }
        let now = CACurrentMediaTime()
        if !isVisible {
            orderFrontRegardless()
        } else if bar.active == orderedAbove, now - lastOrdered < 0.25 {
            return
        }
        // Its window may have been raised over it meanwhile: order again
        // a few times a second, not on every frame.
        order(.above, relativeTo: Int(bar.active))
        orderedAbove = bar.active
        lastOrdered = now
    }
    private var orderedAbove: CGWindowID?
    private var lastOrdered: CFTimeInterval = 0
}

/// Scrolling anywhere on the bar walks the tabs; SwiftUI does not use the
/// wheel here, so the event reaches this view underneath.
private final class ScrollCatchingView: NSView {
    var onScroll: ((Bool) -> Void)?
    private var wheel: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        wheel += event.scrollingDeltaY + event.scrollingDeltaX
        // A trackpad sends many small steps: one tab per 20 points.
        while abs(wheel) >= 20 {
            onScroll?(wheel < 0)
            wheel += wheel > 0 ? -20 : 20
        }
    }
}

@MainActor
@Observable
private final class TabBarModel {
    var tabs: [TilingEngine.Tab] = []
    var active: CGWindowID = 0
    var actions: TabBarActions?
}

private struct TabBarView: View {
    let model: TabBarModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.tabs.enumerated()), id: \.element.windowID) { index, tab in
                TabButton(tab: tab, isActive: tab.windowID == model.active,
                          index: index, count: model.tabs.count,
                          select: { model.actions?.select(tab.windowID) },
                          close: { model.actions?.close(tab.windowID) },
                          reorder: { place in model.actions?.reorder(tab.windowID, place) },
                          detach: { model.actions?.detach(tab.windowID) })
            }
            AddButton { view in model.actions?.add(model.active, view) }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TabButton: View {
    let tab: TilingEngine.Tab
    let isActive: Bool
    let index: Int
    let count: Int
    let select: () -> Void
    let close: () -> Void
    /// Dragged this far along the bar, in tab widths.
    let reorder: (Int) -> Void
    /// Dragged off the bar.
    let detach: () -> Void
    @State private var hovering = false
    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            HStack(spacing: 6) {
                if let icon = NSRunningApplication(processIdentifier: tab.pid)?.icon {
                    Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                }
                // Under 70 pt there is no room for a name worth reading.
                if width > 70 {
                    Text(tab.title.isEmpty ? String(localized: "Window") : tab.title)
                        .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .opacity(hovering || isActive ? 0.8 : 0)
                    .help(String(localized: "Close this window"))
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, width > 70 ? 8 : 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(isActive ? 0.14 : hovering ? 0.07 : 0)))
            .contentShape(Rectangle())
            .offset(x: drag)
            .zIndex(drag == 0 ? 0 : 1)
            .onHover { hovering = $0 }
            .onTapGesture(perform: select)
            .help(tab.title)
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { drag = $0.translation.width }
                    .onEnded { value in
                        drag = 0
                        // Dragged down off the bar: out of the group.
                        if value.translation.height > 24 {
                            detach()
                            return
                        }
                        let places = Int((value.translation.width / max(width, 1)).rounded())
                        guard places != 0 else { return }
                        reorder(min(max(index + places, 0), count - 1))
                    }
            )
        }
        .padding(.vertical, 3)
    }
}

/// The + button; hands its own view to the menu so it opens below it.
private struct AddButton: NSViewRepresentable {
    let action: (NSView) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: String(localized: "New tab"))!,
                              target: context.coordinator, action: #selector(Coordinator.pressed(_:)))
        button.isBordered = false
        button.toolTip = String(localized: "New window in this group")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    @MainActor
    final class Coordinator: NSObject {
        var action: (NSView) -> Void
        init(action: @escaping (NSView) -> Void) { self.action = action }
        @objc func pressed(_ sender: NSButton) { action(sender) }
    }
}
