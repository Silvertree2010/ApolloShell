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
            add: { [weak self] shown, button in self?.showNewTabMenu(for: shown, from: button) }
        )
    }

    /// The + menu: running apps first, then every installed one. Picking an
    /// app opens a new window of it that joins this group.
    private func showNewTabMenu(for shown: CGWindowID, from view: NSView) {
        let menu = NSMenu()
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleURL != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        for app in running {
            menu.addItem(item(title: app.localizedName ?? "App", icon: app.icon) { [weak self] in
                self?.openWindow(of: app, joining: shown)
            })
        }
        let all = NSMenuItem(title: String(localized: "All Apps"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for url in Self.installedApps() {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            submenu.addItem(item(title: url.deletingPathExtension().lastPathComponent, icon: icon) { [weak self] in
                self?.launch(url, joining: shown)
            })
        }
        all.submenu = submenu
        menu.addItem(.separator())
        menu.addItem(all)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }

    private func item(title: String, icon: NSImage?, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title, handler: action)
        icon?.size = NSSize(width: 16, height: 16)
        item.image = icon
        return item
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

    private static func installedApps() -> [URL] {
        let folders = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        let urls = folders.flatMap { folder in
            (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder),
                                                           includingPropertiesForKeys: nil)) ?? []
        }
        return urls.filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

struct TabBarActions {
    let select: (CGWindowID) -> Void
    let close: (CGWindowID) -> Void
    let add: (CGWindowID, NSView) -> Void
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
        let content = NSView()
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

    func update(_ bar: TilingEngine.TabBar) {
        model.tabs = bar.tabs
        model.active = bar.active
        let height = NSScreen.screens.first?.frame.height ?? 0
        // The bar sits in the tile's top strip, a little inset.
        let frame = bar.frame.insetBy(dx: 0, dy: 2)
        setFrame(NSRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height), display: true)
        if !themed {
            glassLayer = ThemedGlass.apply(to: glass, fallbackRadius: 10, previous: glassLayer)
            themed = true
        }
        if !isVisible { orderFrontRegardless() }
        order(.above, relativeTo: Int(bar.active))
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
            ForEach(model.tabs, id: \.windowID) { tab in
                TabButton(tab: tab, isActive: tab.windowID == model.active,
                          select: { model.actions?.select(tab.windowID) },
                          close: { model.actions?.close(tab.windowID) })
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
    let select: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon = NSRunningApplication(processIdentifier: tab.pid)?.icon {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
            }
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
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(isActive ? 0.14 : hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: select)
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
