import AppKit
import ApolloShellCore
import ApplicationServices
import CoreGraphics
import Observation
import os
import SwiftUI
import UniformTypeIdentifiers

/// Dock in the bar (all running and pinned apps, in place of the active
/// window) - with the same content as Apple's Dock: Finder, the pinned
/// apps there, then after a divider the remaining running ones in launch
/// order. Not yet included: recently used apps (show-recents), folders and
/// the trash.
@MainActor
@Observable
final class SidebarDockModel {
    struct Entry: Identifiable, Equatable {
        let bundleID: String
        let name: String
        let icon: NSImage
        let pinned: Bool
        let running: Bool
        /// Hidden (Cmd+H): half-transparent like in Apple's Dock with
        /// "show hidden apps".
        var hidden = false
        var id: String { bundleID }
    }

    private(set) var entries: [Entry] = []
    /// Bundle ID of the frontmost app (highlighted slightly).
    private(set) var frontmost: String?
    /// Just launched, not there yet: the icon bounces (Apple Dock).
    private(set) var launching: Set<String> = []
    /// Counter per bundle ID from Apple's Dock (`DockBadges`).
    private(set) var badges: [String: String] = [:]

    @ObservationIgnored private let live: Bool
    /// Which file manager sits at the top (Nexus > Providers); `nil` in previews.
    @ObservationIgnored private let settings: ShellSettingsStore?
    @ObservationIgnored private var settingsObservation: Task<Void, Never>?
    /// Who sits at Finder's spot (`ProviderFileManager.resolve`): can
    /// neither be removed nor moved, just like Finder in Apple's Dock.
    @ObservationIgnored private var fileManagerID = AppleDockPrefs.finder
    @ObservationIgnored private var badgeTimer: Timer?
    /// A read pass is still running; the next tick is skipped.
    @ObservationIgnored private var badgeReading = false
    /// No bar visible (fullscreen): don't read counters. Set by the bar
    /// manager, like for CPU and weather.
    var badgesPaused = false {
        didSet {
            guard live, badgesPaused != oldValue else { return }
            if badgesPaused { stopBadgeTimer() } else { startBadgeTimer() }
        }
    }
    /// Every 3 s: Apple's Dock doesn't report counter changes, and a read
    /// pass is a handful of accessibility calls (~ms).
    private static let badgeInterval: TimeInterval = 3
    private static let dockDomain = "com.apple.dock" as CFString
    /// Icons from the file system are expensive; loading them once is enough.
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private let ownBundleID = Bundle.main.bundleIdentifier
    @ObservationIgnored private let log = Logger(category: "dock")

    init(settings: ShellSettingsStore) {
        live = true
        self.settings = settings
        frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        refresh()
        // Different file manager in Nexus: applies immediately. First
        // delivers the current value (one extra pass, doesn't hurt), then
        // every change; lives as long as the bar.
        settingsObservation = Task { [weak self, settings] in
            for await _ in Observations({ settings.settings.providers.fileManager }) {
                self?.refresh()
            }
        }
        // Lives as long as the bar, and thus the process.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.activated(id) }
        }
        startBadgeTimer()
    }

    /// For the preview: fixed entries, reads and starts nothing.
    init(preview entries: [Entry], frontmost: String?, badges: [String: String] = [:]) {
        live = false
        settings = nil
        self.entries = entries
        self.frontmost = frontmost
        self.badges = badges
    }

    private func startBadgeTimer() {
        guard badgeTimer == nil else { return }
        pollBadges()
        badgeTimer = .repeating(every: Self.badgeInterval, tolerance: 0.5, owner: self) { $0.pollBadges() }
    }

    private func stopBadgeTimer() {
        badgeTimer?.invalidate()
        badgeTimer = nil
    }

    /// Reads off the main thread: accessibility calls into Apple's Dock
    /// can hang and wait until timeout, and the bar shouldn't stall
    /// because of that.
    private func pollBadges() {
        guard !badgeReading else { return }
        badgeReading = true
        Task { [weak self] in
            let next = await DockBadges.readOffMain()
            guard let self else { return }
            self.badgeReading = false
            if next != self.badges { self.badges = next }
        }
    }

    /// Freshly reads Apple's Dock setting (Synchronize picks up changes
    /// the Dock process has written since the last read) and rebuilds
    /// everything.
    func refresh() {
        guard live else { return }
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [Any] ?? []
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != ownBundleID
        }
        var running: [String: NSRunningApplication] = [:]
        for app in apps {
            if let id = app.bundleIdentifier, running[id] == nil { running[id] = app }
        }
        // At the top, the file manager from Nexus > Providers, as long as
        // it's installed, otherwise ForkLift or Finder. Finder only
        // disappears if something else replaces it (it always runs and
        // would otherwise reappear under "running" anyway).
        let fileManager = ProviderFileManager.resolve(setting: settings?.settings.providers.fileManager) {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
        if fileManager != fileManagerID {
            // The folder icon is tied to the slot, not to the app: both need to be redone.
            icons[fileManagerID] = nil
            icons[fileManager] = nil
            fileManagerID = fileManager
        }
        let slots = DockLayout.slots(
            pinned: AppleDockPrefs.pinnedBundleIDs(tiles, fileManager: fileManager),
            running: apps.compactMap(\.bundleIdentifier),
            hidden: ProviderFileManager.hidden(for: fileManager),
            alwaysRunning: [fileManager]
        ) { id in
            running[id] != nil || NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
        }
        let next = slots.compactMap { slot -> Entry? in
            let app = running[slot.bundleID]
            guard let url = app?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: slot.bundleID)
            else { return nil }
            return Entry(
                bundleID: slot.bundleID,
                name: app?.localizedName ?? FileManager.default.displayName(atPath: url.path),
                icon: icon(for: slot.bundleID, app: app, url: url),
                pinned: slot.pinned,
                running: slot.running,
                hidden: app?.isHidden ?? false
            )
        }
        if next != entries { entries = next }
        // Finished launching: stop bouncing.
        let started = launching.intersection(running.keys)
        if !started.isEmpty { launching.subtract(started) }
    }

    func runningApp(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// Click on an icon, with the modifiers of Apple's Dock
    /// (`DockClickAction`). The state (running, frontmost, windows) goes
    /// into the pure decision `DockClick.actions`; only execution happens
    /// here.
    func click(_ entry: Entry, modifiers: NSEvent.ModifierFlags) {
        guard live else { return }
        perform(entry, command: modifiers.contains(.command), option: modifiers.contains(.option))
    }

    /// Builds the state for `entry`, lets `DockClick` decide and executes
    /// the actions in order.
    private func perform(_ entry: Entry, command: Bool, option: Bool) {
        let app = runningApp(entry.bundleID)
        let windows = app.map { DockWindows.list(pid: $0.processIdentifier) } ?? []
        let visible = windows.filter { !$0.minimized }
        // Only non-minimized windows can be "here": which of them are
        // actually on screen right now is decided by the current space
        // (`onScreenWindowIDs`), not the accessibility list - that
        // doesn't know about spaces.
        let onScreen = app.map { DockWindows.onScreenWindowIDs(pid: $0.processIdentifier) } ?? []
        let onActiveSpace = visible.filter { $0.windowID.map(onScreen.contains) ?? false }
        // The accessibility list doesn't know about windows on other
        // desktops (it only shows the current one), so from the system's
        // window list instead: everything minus the ones here minus the
        // minimized ones.
        let minimizedIDs = Set(windows.filter(\.minimized).compactMap(\.windowID))
        let elsewhere = app.map {
            DockWindows.allWindowIDs(pid: $0.processIdentifier, requireSpace: !$0.isHidden)
                .subtracting(onScreen)
                .subtracting(minimizedIDs)
                .count
        } ?? 0
        let previous = NSWorkspace.shared.frontmostApplication
        let frontmost = app != nil && app?.processIdentifier == previous?.processIdentifier
        // Only check when it actually comes up as a question (an
        // accessibility call of its own): already frontmost, with at
        // least one window here. When clicking the already-frontmost app,
        // only cycle if something is really in the way, not with several
        // windows freely side by side.
        let coveredWindowID: CGWindowID? = (frontmost && !onActiveSpace.isEmpty)
            ? app.flatMap { DockWindows.coveredWindowID(pid: $0.processIdentifier) }
            : nil
        let state = DockClickState(
            running: app != nil,
            launching: launching.contains(entry.bundleID),
            frontmost: frontmost,
            hidden: app?.isHidden ?? false,
            windowsOnActiveSpace: onActiveSpace.count,
            windowsElsewhere: elsewhere,
            minimizedWindows: windows.count(where: \.minimized),
            hasCoveredWindow: coveredWindowID != nil,
            command: command,
            option: option
        )
        let actions = DockClick.actions(for: state)
        for action in actions {
            switch action {
            case .launch:
                open(entry)
            case .unhide:
                _ = app?.unhide()
            case .activate:
                app?.activate()
            case .raiseWindowElsewhere:
                // Only through the window itself does macOS switch the
                // desktop (measured 20.09.: `activate()` fetches none).
                // Without a remote window the old way stays, better than
                // nothing.
                if let app, let window = windowElsewhere(of: app, onScreen: onScreen) {
                    DockWindows.raise(window, of: app)
                } else {
                    app?.activate()
                }
            case .raiseWindowOnActiveSpace:
                // The frontmost window here: it brings the app forward
                // along with it, no extra `.activate` needed.
                if let app, let window = onActiveSpace.first {
                    DockWindows.raise(window, of: app)
                }
            case .raiseCoveredWindow:
                if let app, let coveredWindowID, let window = windows.first(where: { $0.windowID == coveredWindowID }) {
                    DockWindows.raise(window, of: app)
                }
            case .unminimizeLast:
                // No timestamps via accessibility: the frontmost minimized
                // window in the list is the closest thing to "most
                // recently minimized" (it was frontmost right before being
                // minimized). `raise` brings it out of the Dock, lifts it and
                // brings the app along - also when it was put away on another
                // desktop.
                if let app, let last = windows.first(where: \.minimized) {
                    DockWindows.raise(last, of: app)
                }
            case .newWindow:
                if let app,
                   let command = DockAppCommands.commands(pid: app.processIdentifier)
                       .first(where: { $0.kind == .newItem }) {
                    DockAppCommands.press(command, of: app)
                }
            case .hidePrevious:
                if let previous, previous.bundleIdentifier != entry.bundleID, previous.bundleIdentifier != ownBundleID {
                    previous.hide()
                }
            case .reveal:
                reveal(entry)
            }
        }
    }

    /// A window of the app on another desktop. `kAXWindowsAttribute` only
    /// knows the current one, hence the list across all spaces (remote
    /// token); whatever lies on screen right now drops out. Fetched only
    /// here, not for the state already: the call costs milliseconds and is
    /// only needed for this case.
    private func windowElsewhere(of app: NSRunningApplication, onScreen: Set<CGWindowID>) -> DockWindows.Window? {
        DockWindows.list(pid: app.processIdentifier, allSpaces: true).first { window in
            !window.minimized && !(window.windowID.map(onScreen.contains) ?? false)
        }
    }

    /// If the app is already frontmost and has several windows: bring the
    /// next one forward (`DockWindowCycle`). `false` = nothing changed.
    private func cycleWindows(of entry: Entry) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        let isFront = front.bundleIdentifier == entry.bundleID
        // Only fetch the window list if it's actually relevant (AX call).
        let windows = isFront ? DockWindows.list(pid: front.processIdentifier).filter { !$0.minimized } : []
        guard let index = DockWindowCycle.indexToRaise(isFrontmost: isFront, visibleWindows: windows.count) else {
            return false
        }
        DockWindows.raise(windows[index], of: front)
        return true
    }

    /// Files dropped on the icon: open with this app, as in Apple's Dock.
    /// Launches it for that if needed.
    func openFiles(_ urls: [URL], with entry: Entry) {
        let files = urls.filter(\.isFileURL)
        guard live, !files.isEmpty,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID)
        else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(files, withApplicationAt: app, configuration: configuration) { [log] _, error in
            if let error {
                log.error("Dock: files not opened: \((error as NSError).code, privacy: .public)")
            }
        }
    }

    /// Scrolling on the icon: if the app is running, bring it forward, or
    /// - if it's already frontmost - its next window. Scrolling doesn't
    /// launch apps that aren't running (accidentally while scrolling past).
    func scroll(_ entry: Entry) {
        guard live, runningApp(entry.bundleID) != nil else { return }
        if !cycleWindows(of: entry) { perform(entry, command: false, option: false) }
    }

    // MARK: Pinning, removing, moving (writes Apple's Dock list)

    /// Pinned in Apple's Dock - not just at the top as the file manager.
    func isPinnedInDock(_ entry: Entry) -> Bool {
        entry.pinned && entry.bundleID != fileManagerID
    }

    /// The file manager at the top is fixed, like Finder in Apple's Dock.
    func canPin(_ entry: Entry) -> Bool {
        entry.bundleID != fileManagerID
    }

    func togglePin(_ entry: Entry) {
        guard live, canPin(entry) else { return }
        if isPinnedInDock(entry) {
            writeTiles { AppleDockPrefs.removing(entry.bundleID, from: $0) }
        } else {
            place(entry.bundleID, onto: nil)
        }
    }

    /// Icon `source` dragged onto `target`: takes its spot (dragged down,
    /// goes behind it; dragged up, goes before it - like reordering in
    /// Apple's Dock). A merely-running app gets pinned in the process.
    /// Onto the file manager at the top: goes to the front; onto a
    /// merely-running app or `nil`: to the end of the pinned ones.
    func place(_ source: String, onto target: String?) {
        guard live, source != fileManagerID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source)
        else { return }
        let ids = entries.map(\.bundleID)
        let position: AppleDockPrefs.Position
        if let target, target == fileManagerID {
            position = .start
        } else if let target, let entry = entries.first(where: { $0.bundleID == target }), isPinnedInDock(entry) {
            let from = ids.firstIndex(of: source) ?? ids.count
            let to = ids.firstIndex(of: target) ?? ids.count
            position = from < to ? .after(target) : .before(target)
        } else {
            position = .end
        }
        let label = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        writeTiles {
            AppleDockPrefs.placing(source, at: position, in: $0) {
                AppleDockPrefs.tile(bundleID: source, url: url, label: label, guid: Int.random(in: 1...Int(Int32.max)))
            }
        }
    }

    /// Changes "persistent-apps" in Apple's Dock setting via cfprefsd (not
    /// bypassing the file, otherwise the bar would see the old state). The
    /// hidden Dock itself only re-reads the list at the next login; until
    /// then the bar is authoritative.
    private func writeTiles(_ change: ([Any]) -> [Any]) {
        CFPreferencesAppSynchronize(Self.dockDomain)
        let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, Self.dockDomain) as? [Any] ?? []
        let next = change(tiles)
        CFPreferencesSetAppValue("persistent-apps" as CFString, next as NSArray as CFArray, Self.dockDomain)
        CFPreferencesAppSynchronize(Self.dockDomain)
        refresh()
    }

    /// "Show in <file manager>": marked when the chosen file manager is
    /// also the system's file viewer (NSFileViewer, only read); otherwise
    /// it opens the containing folder (`ProviderFileManager.reveal`).
    func reveal(_ entry: Entry) {
        guard live, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID) else { return }
        let viewer = UserDefaults.standard.string(forKey: "NSFileViewer")
        switch ProviderFileManager.reveal(fileManager: fileManagerID, systemFileViewer: viewer) {
        case .selectInFileViewer:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .openFolder(let id):
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                // Just uninstalled: better the system viewer than nothing.
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([url.deletingLastPathComponent()], withApplicationAt: app,
                                    configuration: configuration) { [log] _, error in
                if let error {
                    log.error("Dock: folder not shown: \((error as NSError).code, privacy: .public)")
                }
            }
        }
    }

    /// For "Show in ..." in the Dock menu: the file manager at the top.
    var fileManagerName: String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: fileManagerID) else { return "Finder" }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Like a click in Apple's Dock: if it's running, bring it forward
    /// (without a window, the app opens a new one), otherwise launch it -
    /// then the icon bounces until it's there (at most 15 s, in case the
    /// launch fails).
    private func open(_ entry: Entry) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID) else { return }
        if runningApp(entry.bundleID) == nil {
            launching.insert(entry.bundleID)
            let id = entry.bundleID
            Timer.once(after: 15, owner: self) { _ = $0.launching.remove(id) }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [log] _, error in
            if let error {
                log.error("Dock: launch failed: \((error as NSError).code, privacy: .public)")
            }
        }
    }

    private func activated(_ id: String?) {
        // Nexus brings the launcher forward itself; then the app before it still counts.
        guard let id, id != ownBundleID, id != frontmost else { return }
        frontmost = id
    }

    private func icon(for id: String, app: NSRunningApplication?, url: URL) -> NSImage {
        if let cached = icons[id] { return cached }
        // The file manager at the top stands for "the file manager" and
        // therefore looks like an ordinary folder - whichever app it is,
        // except Finder with its own face. Only here in the bar, the app
        // itself stays untouched (otherwise its signature and self-update
        // would break).
        let icon = id == fileManagerID && id != AppleDockPrefs.finder
            ? DockIconArt.folder
            : app?.icon ?? NSWorkspace.shared.icon(forFile: url.path)
        icons[id] = icon
        return icon
    }
}

/// Custom folder icon for the file manager, in the style of its app icons.
///
/// It has the "Clear" (light) icon style: macOS then renders app icons as
/// a gray glass tile with a light-colored motif. The generic folder icon
/// (`icon(for: .folder)`) doesn't get this style and was yellow - "0%
/// match with the rest" (09-14). So it was rebuilt: values measured from a
/// screenshot of the real icons (tile gray 0.62 at the top down to 0.57 at
/// the bottom, motif near-white), tile like Apple's app icons at 82% of
/// the area with a 22.5% corner radius. Vector, so sharp at any resolution.
@MainActor
enum DockIconArt {
    static let folder: NSImage = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
        let side = rect.width * 0.82
        let tile = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        let shape = NSBezierPath(roundedRect: tile, xRadius: side * 0.225, yRadius: side * 0.225)
        NSGradient(starting: NSColor(white: 0.62, alpha: 1), ending: NSColor(white: 0.55, alpha: 1))?
            .draw(in: shape, angle: -90)
        // Fine light edge like the glass of the real tiles.
        NSColor(white: 1, alpha: 0.18).setStroke()
        shape.lineWidth = rect.width * 0.012
        shape.stroke()

        let config = NSImage.SymbolConfiguration(pointSize: side * 0.46, weight: .medium)
            .applying(.init(paletteColors: [NSColor(white: 0.97, alpha: 1)]))
        if let glyph = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let size = glyph.size
            glyph.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                  width: size.width, height: size.height))
        }
        return true
    }
}

/// The icons stacked vertically, centered between spaces and the clock. If
/// not all fit, the column can be scrolled (without a scrollbar, since
/// Apple's Dock would instead shrink itself - at 44 pt width that would be
/// too small).
///
/// Nexus > Bar > Dock: show pinned only, icon size. This only filters the
/// view - the model still reads everything.
struct SidebarDock: View {
    let model: SidebarDockModel
    var options = BarDockOptions()
    /// Preview in Nexus: no hover, no click, no menu, no dragging - nothing
    /// there should really launch, quit or pin an app.
    @Environment(\.barPreview) private var preview
    @Environment(\.shellStyle) private var dockStyle

    private var entries: [SidebarDockModel.Entry] {
        options.showRunning ? model.entries : model.entries.filter(\.pinned)
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            column
            ScrollView(.vertical, showsIndicators: false) {
                column.padding(.vertical, 8)
            }
            // Fade out softly at top and bottom instead of a hard cut
            // (Apple: scroll edge instead of a divider line).
            .mask {
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                            .init(color: .black, location: 0.96), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .frame(maxHeight: .infinity)
        .animation(SidebarMotion.spatial, value: entries.map(\.id))
    }

    private var column: some View {
        let entries = entries
        let split = entries.firstIndex { !$0.pinned }
        // With theme: `--apollo-dock-spacing` between the icons,
        // `--apollo-dock-icon-size` for their size.
        return VStack(spacing: dockStyle.dockSpacing(4)) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                // Divider between pinned and merely-running, as in Apple's Dock.
                if index == split, index > 0 {
                    Capsule()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 20, height: 2)
                        .padding(.vertical, 3)
                }
                SidebarDockItem(
                    entry: entry,
                    iconSize: dockStyle.dockIconSize(CGFloat(options.iconSize.points)),
                    interactive: !preview,
                    active: entry.bundleID == model.frontmost,
                    launching: model.launching.contains(entry.bundleID),
                    badge: model.badges[entry.bundleID],
                    onClick: { model.click(entry, modifiers: $0) },
                    onMenu: { DockMenu.show(for: entry, model: model, at: $0) },
                    onScroll: { model.scroll(entry) },
                    onDropFiles: { model.openFiles($0, with: entry) },
                    onDropApp: { model.place($0, onto: entry.bundleID) }
                )
            }
        }
        // Full bar width: otherwise the column sits at the left edge
        // within the ScrollView, and the running-indicator dots (outside
        // the icon on the left) get cut off - screenshot from 09-14.
        .frame(maxWidth: .infinity)
    }
}

/// An app icon: running with a dot on the left edge (the outer side, as in
/// Apple's Dock at the screen edge), highlighted slightly when frontmost,
/// hover like the bar's other icons, darker when pressed. Mouse logic
/// (click, hold, right-click) is in `DockMouseCatcher`.
private struct SidebarDockItem: View {
    let entry: SidebarDockModel.Entry
    /// Edge length of the icon (Nexus); the button stays 32 x 32.
    let iconSize: CGFloat
    /// Off: image only, no mouse views (preview in Nexus).
    let interactive: Bool
    let active: Bool
    let launching: Bool
    let badge: String?
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onMenu: (NSView) -> Void
    let onScroll: () -> Void
    let onDropFiles: ([URL]) -> Void
    let onDropApp: (String) -> Void
    @State private var hovering = false
    @State private var pressed = false
    /// Files are currently being dragged over it: highlight like in Apple's Dock.
    @State private var dropTarget = false
    @Environment(\.shellStyle) private var style

    var body: some View {
        Image(nsImage: entry.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: iconSize, height: iconSize)
            .brightness(pressed || dropTarget ? -0.25 : 0)
            .opacity(entry.hidden ? 0.5 : 1)
            .modifier(DockBounce(active: launching))
            .frame(width: 32, height: 32)
            .background(Color.primary.opacity(hovering || dropTarget ? 0.14 : active ? 0.10 : 0), in: .rect(cornerRadius: 9))
            // Counter like in Apple's Dock: red capsule at the top right.
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(style.danger, in: .capsule)
                        .fixedSize()
                        .offset(x: 5, y: -3)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: badge)
            .overlay(alignment: .leading) {
                if entry.running {
                    Circle()
                        // With theme: `--apollo-dock-indicator-color`.
                        .fill(style.paint(.dockIndicator, or: Color.primary.opacity(0.65)))
                        .frame(width: 4, height: 4)
                        .offset(x: -5)
                }
            }
            .overlay {
                if interactive {
                    DockMouseCatcher(
                        bundleID: entry.bundleID, dragImage: entry.icon,
                        onClick: onClick, onMenu: onMenu, onPress: { pressed = $0 },
                        onScroll: onScroll, onDropFiles: onDropFiles, onDropApp: onDropApp,
                        onDropTarget: { dropTarget = $0 }
                    )
                }
            }
            // Not `onHover`: the bar belongs to an app that's never active.
            .background {
                if interactive { HoverTracker { hovering = $0 } }
            }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.15), value: active)
            .help(entry.name)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.running ? String(localized: "\(entry.name), running") : entry.name)
            .accessibilityAddTraits(.isButton)
    }
}

/// Bounces on launch like in Apple's Dock - there, away from the screen
/// edge, here, so to the right. Only while launching: the phase animator
/// otherwise keeps running and costs CPU time. Decelerating going up,
/// like falling going down.
private struct DockBounce: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.phaseAnimator([0.0, 10.0]) { view, offset in
                view.offset(x: offset)
            } animation: { offset in
                offset > 0 ? .easeOut(duration: 0.22) : .easeIn(duration: 0.22)
            }
        } else {
            content
        }
    }
}
