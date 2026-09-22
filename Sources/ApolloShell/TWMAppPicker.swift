import ApolloShellCore
import AppKit
import SwiftUI

/// The tab bar's + : a small glass panel below the button with a search
/// field. Open apps come first, then every installed one; typing filters
/// both (fuzzy, like the launcher). Arrows move, Return picks, Escape or a
/// click elsewhere closes it.
@MainActor
final class TWMAppPicker {
    enum Choice {
        case running(NSRunningApplication)
        case installed(URL)
    }

    private var panel: PickerPanel?

    /// Shows the picker below `view`; `pick` gets the chosen app.
    func show(below view: NSView, pick: @escaping (Choice) -> Void) {
        close()
        guard let window = view.window else { return }
        let size = NSSize(width: 320, height: 380)
        let button = window.convertToScreen(view.convert(view.bounds, to: nil))
        var origin = NSPoint(x: button.minX, y: button.minY - size.height - 6)
        if let screen = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
            origin.y = max(origin.y, screen.minY + 8)
        }
        let panel = PickerPanel(size: size) { [weak self] choice in
            self?.close()
            if let choice { pick(choice) }
        }
        panel.setFrameOrigin(origin)
        self.panel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

@MainActor
private final class PickerPanel: ShellPanel, NSWindowDelegate {
    private let finish: (TWMAppPicker.Choice?) -> Void
    private var finished = false

    init(size: NSSize, finish: @escaping (TWMAppPicker.Choice?) -> Void) {
        self.finish = finish
        super.init(size: size, level: .floating, behavior: [.ignoresCycle, .transient, .moveToActiveSpace],
                   takesKeyboard: true)
        delegate = self
        let glass = NSGlassEffectView()
        let hosting = NSHostingView(rootView: PickerView(done: { [weak self] in self?.done($0) }).shellTheme())
        glass.contentView = hosting
        contentView = glass
        ThemedGlass.apply(to: glass, fallbackRadius: 14)
    }

    private func done(_ choice: TWMAppPicker.Choice?) {
        guard !finished else { return }
        finished = true
        finish(choice)
    }

    // A click elsewhere closes it.
    func windowDidResignKey(_ notification: Notification) { done(nil) }
}

/// One row: an open app or an installed one.
private struct PickerItem: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let isRunning: Bool
    let choice: TWMAppPicker.Choice
}

private struct PickerView: View {
    let done: (TWMAppPicker.Choice?) -> Void
    @Environment(\.shellStyle) private var style
    @State private var query = ""
    @State private var selection = 0
    /// Built once when the panel opens (icons are not free).
    @State private var running: [PickerItem] = Self.runningItems()
    @State private var rest: [PickerItem] = []
    @FocusState private var searching: Bool

    private static func runningItems() -> [PickerItem] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleURL != nil }
            .map { app in
                PickerItem(id: "run:\(app.processIdentifier)", name: app.localizedName ?? "App",
                           icon: app.icon ?? NSImage(), isRunning: true, choice: .running(app))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var items: [PickerItem] {
        let all = running + rest
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        let matcher = FuzzyMatcher()
        var scored: [(item: PickerItem, score: Int)] = []
        for item in all {
            guard let score = matcher.score(q, in: item.name) else { continue }
            // Open apps get a small head start among equally good hits.
            scored.append((item, score + (item.isRunning ? 5 : 0)))
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.item.name.localizedStandardCompare(rhs.item.name) == .orderedAscending
        }
        return scored.map(\.item)
    }

    var body: some View {
        let items = items
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(style.secondaryText)
                TextField("New window of…", text: $query)
                    .textFieldStyle(.plain)
                    .font(style.font(size: 13))
                    .focused($searching)
                    .onSubmit { pick(items) }
            }
            .padding(12)
            Divider()
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, selected: index == selection)
                                .id(index)
                                .onTapGesture { done(item.choice) }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selection) { _, new in scroller.scrollTo(new) }
            }
        }
        .onChange(of: query) { selection = 0 }
        .onKeyPress(.downArrow) {
            selection = min(selection + 1, max(items.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selection = max(selection - 1, 0)
            return .handled
        }
        .onKeyPress(.escape) {
            done(nil)
            return .handled
        }
        .task {
            searching = true
            let scanned = await Task.detached(priority: .userInitiated) { AppCatalog().scan() }.value
            let open = Set(running.compactMap { item -> String? in
                if case .running(let app) = item.choice { return app.bundleIdentifier }
                return nil
            })
            rest = scanned
                .filter { $0.bundleID.map { !open.contains($0) } ?? true }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { entry in
                    PickerItem(id: entry.url.path, name: entry.name,
                               icon: NSWorkspace.shared.icon(forFile: entry.url.path),
                               isRunning: false, choice: .installed(entry.url))
                }
        }
    }

    private func pick(_ items: [PickerItem]) {
        guard items.indices.contains(selection) else { return }
        done(items[selection].choice)
    }

    private func row(_ item: PickerItem, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: item.icon).resizable().interpolation(.high).frame(width: 20, height: 20)
            Text(item.name).font(style.font(size: 13)).lineLimit(1)
            Spacer(minLength: 6)
            if item.isRunning {
                Circle().fill(style.secondaryText).frame(width: 4, height: 4)
                    .help(String(localized: "Open"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? style.accent.opacity(0.25) : .clear))
        .contentShape(Rectangle())
    }
}
