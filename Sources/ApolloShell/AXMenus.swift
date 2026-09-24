import AppKit
import ApolloShellCore
import ApplicationServices
import os

/// Reads the menus of other apps through accessibility and presses their
/// entries: the frontmost app's menu bar (`AXMenuBar`) and every app's
/// status items (`AXExtrasMenuBar`). Measured in the VM (spec topbar.md):
/// the whole tree reads without the menu opening on screen - accessibility
/// runs menuNeedsUpdate itself, so dynamic entries are current - and
/// AXPress on an entry of a closed menu carries it out.
///
/// Read raw here, interpret in the core (`AppMenuTree`, tested). Every call
/// waits for the other app, so everything runs on one serial queue of its
/// own, never on the main thread - the pattern of `AppleDockMenu`.
enum AXMenus {
    private static let log = Logger(category: "axmenus")
    /// A hung app holds the queue at most this long per request.
    private static let timeout: Float = 1
    /// No menu has more; a guard against an app that builds entries forever
    /// ("Open Recent" of a thousand files, a broken delegate).
    private static let entryBudget = 3000

    private static let queue = DispatchQueue(label: AppIdentity.scoped("axmenus"), qos: .userInitiated)

    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    // MARK: - The app's menu bar

    /// The top-level titles, Apple's menu first ("Apple", "Finder", "File"
    /// ...). `nil` without the permission or without a menu bar.
    static func menuBarTitles(pid: pid_t) async -> [String]? {
        guard !isOwn(pid) else { return nil }
        return await run {
            guard AXIsProcessTrusted(), let bar = menuBar(pid: pid) else { return nil }
            return AX.elements(bar, kAXChildrenAttribute).map { AX.string($0, kAXTitleAttribute) ?? "" }
        }
    }

    /// The entries of top-level menus, read fresh: the menu may have changed
    /// since the titles were read ("Open Recent", window lists).
    static func menuBarMenus(pid: pid_t, indices: [Int]) async -> [(title: String, index: Int, nodes: [AppMenuNode])] {
        guard !isOwn(pid) else { return [] }
        return await run {
            guard AXIsProcessTrusted(), let bar = menuBar(pid: pid) else { return [] }
            let items = AX.elements(bar, kAXChildrenAttribute)
            var budget = entryBudget
            return indices.compactMap { index in
                guard items.indices.contains(index) else { return nil }
                let title = AX.string(items[index], kAXTitleAttribute) ?? ""
                let entries = submenu(of: items[index]).map { read($0, depth: 0, budget: &budget) } ?? []
                return (title, index, AppMenuTree.nodes(from: entries, path: [AXMenuStep(title: title, index: index)]))
            }
        }
    }

    /// Carries out an entry of the menu bar; the first step is the top-level
    /// menu.
    static func pressMenuBar(pid: pid_t, path: [AXMenuStep]) async -> Bool {
        guard !isOwn(pid) else { return false }
        return await run {
            guard let bar = menuBar(pid: pid), let first = path.first else { return false }
            let items = AX.elements(bar, kAXChildrenAttribute)
            guard let index = first.resolve(in: items.map { AX.string($0, kAXTitleAttribute) ?? "" }) else { return false }
            return press(from: items[index], rest: Array(path.dropFirst()))
        }
    }

    // MARK: - Status items

    /// Every other app's status items, raw - the core picks and orders
    /// (`StatusItemOrder`). Only apps that can have a status item: a
    /// background-only process has no user interface at all.
    ///
    /// Never our own process: AppKit answers an accessibility request to
    /// itself in-process, on the asking thread - AppKit and SwiftUI off the
    /// main thread (the TWM crashes of 21.09.), and while one of our menus
    /// tracks on the main thread the request can hold this queue up. Our
    /// own item (Nexus) comes from its NSStatusItem instead.
    static func statusItems() async -> [StatusItemRecord] {
        let own = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited && $0.processIdentifier != own
                && !StatusItemOrder.isSystem(bundleID: $0.bundleIdentifier) }
            .map { (pid: $0.processIdentifier, bundleID: $0.bundleIdentifier) }
        return await run {
            guard AXIsProcessTrusted() else { return [] }
            var records: [StatusItemRecord] = []
            for app in apps {
                let element = AXUIElementCreateApplication(app.pid)
                // Short: an app that hangs here must not hold the whole row up.
                AXUIElementSetMessagingTimeout(element, 0.25)
                guard let extras = AX.element(element, "AXExtrasMenuBar") else { continue }
                for (index, item) in AX.elements(extras, kAXChildrenAttribute).enumerated() {
                    records.append(StatusItemRecord(
                        pid: app.pid, bundleID: app.bundleID, index: index, frame: AX.frame(of: item) ?? .zero,
                        title: AX.string(item, kAXTitleAttribute) ?? "",
                        label: AX.string(item, kAXDescriptionAttribute) ?? ""
                    ))
                }
            }
            return records
        }
    }

    /// The menu of a status item, read while it stays closed. `nil` when it
    /// has none: then it opens a popover or a window of its own, which only
    /// its app can show (`pressStatusItem` with an empty path).
    static func statusItemMenu(pid: pid_t, index: Int) async -> [AppMenuNode]? {
        guard !isOwn(pid) else { return nil }
        return await run {
            guard let item = statusItem(pid: pid, index: index), let menu = submenu(of: item) else { return nil }
            var budget = entryBudget
            let entries = read(menu, depth: 0, budget: &budget)
            return entries.isEmpty ? nil : AppMenuTree.nodes(from: entries)
        }
    }

    /// Presses an entry of a status item's menu, or with an empty path the
    /// item itself - its popover opens where Apple's menu bar has the item.
    static func pressStatusItem(pid: pid_t, index: Int, path: [AXMenuStep]) async -> Bool {
        guard !isOwn(pid) else { return false }
        return await run {
            guard let item = statusItem(pid: pid, index: index) else { return false }
            return press(from: item, rest: path)
        }
    }

    // MARK: - Walking

    /// Our own process: never asked through accessibility, see `statusItems`.
    static func isOwn(_ pid: pid_t) -> Bool {
        pid == ProcessInfo.processInfo.processIdentifier
    }

    private static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        return app
    }

    private static func menuBar(pid: pid_t) -> AXUIElement? {
        AX.element(application(pid), kAXMenuBarAttribute)
    }

    private static func statusItem(pid: pid_t, index: Int) -> AXUIElement? {
        guard AXIsProcessTrusted(), let extras = AX.element(application(pid), "AXExtrasMenuBar") else { return nil }
        let items = AX.elements(extras, kAXChildrenAttribute)
        return items.indices.contains(index) ? items[index] : nil
    }

    /// The menu hanging off a menu bar item or an entry.
    private static func submenu(of item: AXUIElement) -> AXUIElement? {
        AX.elements(item, kAXChildrenAttribute).first { AX.string($0, kAXRoleAttribute) == kAXMenuRole as String }
    }

    /// Walks `rest` down from `start` and presses where it ends.
    private static func press(from start: AXUIElement, rest: [AXMenuStep]) -> Bool {
        var current = start
        for step in rest {
            guard let menu = submenu(of: current) else { return false }
            let children = AX.elements(menu, kAXChildrenAttribute)
            guard let index = step.resolve(in: children.map { AX.string($0, kAXTitleAttribute) ?? "" }) else {
                log.notice("menu entry gone: \(step.title, privacy: .public)")
                return false
            }
            current = children[index]
        }
        let result = AXUIElementPerformAction(current, kAXPressAction as CFString)
        if result != .success { log.notice("AXPress failed: \(result.rawValue, privacy: .public)") }
        return result == .success
    }

    private static let attributes: [String] = [
        kAXTitleAttribute, kAXEnabledAttribute, kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute,
        kAXMenuItemCmdGlyphAttribute, kAXMenuItemMarkCharAttribute, kAXChildrenAttribute,
    ]

    /// The entries of a menu, their submenus included. One request per entry
    /// for all its attributes instead of seven.
    private static func read(_ menu: AXUIElement, depth: Int, budget: inout Int) -> [AXMenuEntry] {
        guard depth < AppMenuTree.maximumDepth else { return [] }
        var entries: [AXMenuEntry] = []
        for child in AX.elements(menu, kAXChildrenAttribute) {
            guard budget > 0 else { break }
            budget -= 1
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(child, attributes as CFArray, AXCopyMultipleAttributeOptions(), &raw) == .success,
                  let values = raw as? [Any], values.count == 7
            else { continue }
            // A missing attribute comes back as an AXValue carrying the error;
            // the casts leave it at the default.
            let submenu = (values[6] as? [AXUIElement])?.first { AX.string($0, kAXRoleAttribute) == kAXMenuRole as String }
            entries.append(AXMenuEntry(
                title: values[0] as? String ?? "",
                enabled: (values[1] as? NSNumber)?.boolValue ?? true,
                commandCharacter: values[2] as? String ?? "",
                commandModifiers: (values[3] as? NSNumber)?.intValue ?? 0,
                commandGlyph: (values[4] as? NSNumber)?.intValue ?? 0,
                mark: values[5] as? String ?? "",
                hasSubmenu: submenu != nil,
                children: submenu.map { read($0, depth: depth + 1, budget: &budget) } ?? []
            ))
        }
        return entries
    }
}

/// Builds our NSMenu out of the nodes: titles, shortcuts drawn by AppKit,
/// ticks, greyed entries, submenus, separators and Option alternates. A
/// choice hands the node's path to `press`.
@MainActor
enum AXMenuBuilder {
    static func menu(_ nodes: [AppMenuNode], press: @escaping @MainActor ([AXMenuStep]) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        append(nodes, to: menu, press: press)
        return menu
    }

    static func append(_ nodes: [AppMenuNode], to menu: NSMenu, press: @escaping @MainActor ([AXMenuStep]) -> Void) {
        for node in nodes {
            if node.isSeparator {
                menu.addItem(.separator())
                continue
            }
            let item: NSMenuItem
            if node.hasSubmenu {
                item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
                item.submenu = self.menu(node.children, press: press)
            } else {
                let path = node.path
                item = ClosureMenuItem(node.title) { press(path) }
            }
            item.isEnabled = node.enabled
            item.state = switch node.mark {
            case .none: .off
            case .check: .on
            case .mixed: .mixed
            }
            if let shortcut = node.shortcut, !shortcut.keyEquivalent.isEmpty {
                item.keyEquivalent = shortcut.keyEquivalent
            }
            // Also without a key: an alternate differs from its primary only
            // by the modifiers.
            item.keyEquivalentModifierMask = flags(node.modifiers)
            item.isAlternate = node.isAlternate
            menu.addItem(item)
        }
    }

    private static func flags(_ modifiers: MenuModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }

    /// Under the view, flush with its left edge - where Apple's menus open.
    static func popUp(_ menu: NSMenu, below view: NSView) {
        // The view may be gone by the time the menu was read (the bar
        // rebuilt): AppKit throws then, see `NativeAppMenu.popUp`.
        guard view.window != nil else { return }
        let bottom = view.isFlipped ? view.bounds.maxY : view.bounds.minY
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX, y: bottom + (view.isFlipped ? 3 : -3)), in: view)
    }

    /// Without the accessibility permission: one entry that leads there.
    static func permissionMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(String(localized: "Allow Accessibility Access to Show Menus…")) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        })
        return menu
    }
}
