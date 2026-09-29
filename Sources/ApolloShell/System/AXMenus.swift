import AppKit
import ApolloShellCore
import ApplicationServices
import os

enum AXMenus {
    private static let log = Logger(category: "axmenus")
    private static let timeout: Float = 1
    private static let entryBudget = 3000
    private static let queue = DispatchQueue(label: AppIdentity.scoped("axmenus"), qos: .userInitiated)

    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    static func menuBarTitles(pid: pid_t) async -> [String]? {
        guard !isOwn(pid) else { return nil }
        return await run {
            guard AXIsProcessTrusted(), let bar = menuBar(pid: pid) else { return nil }
            return AX.elements(bar, kAXChildrenAttribute).map { AX.string($0, kAXTitleAttribute) ?? "" }
        }
    }

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

    static func pressMenuBar(pid: pid_t, path: [AXMenuStep]) async -> Bool {
        guard !isOwn(pid) else { return false }
        return await run {
            guard let bar = menuBar(pid: pid), let first = path.first else { return false }
            let items = AX.elements(bar, kAXChildrenAttribute)
            guard let index = first.resolve(in: items.map { AX.string($0, kAXTitleAttribute) ?? "" }) else { return false }
            return press(from: items[index], rest: Array(path.dropFirst()))
        }
    }

    static func pressMenuBar(pid: pid_t, titles: [String]) async -> Bool {
        guard !isOwn(pid), let first = titles.first else { return false }
        return await run {
            guard let bar = menuBar(pid: pid) else { return false }
            let items = AX.elements(bar, kAXChildrenAttribute)
            let names = items.map { AX.string($0, kAXTitleAttribute) ?? "" }
            let index = names.firstIndex(of: first) ?? (names.count > 1 && first == "Apple" ? 0 : nil)
            guard let index else { return false }
            return press(from: items[index], rest: titles.dropFirst().map { AXMenuStep(title: $0, index: -1) })
        }
    }

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

    static func statusItemMenu(pid: pid_t, index: Int) async -> [AppMenuNode]? {
        guard !isOwn(pid) else { return nil }
        return await run {
            guard let item = statusItem(pid: pid, index: index), let menu = submenu(of: item) else { return nil }
            var budget = entryBudget
            let entries = read(menu, depth: 0, budget: &budget)
            return entries.isEmpty ? nil : AppMenuTree.nodes(from: entries)
        }
    }

    static func pressStatusItem(pid: pid_t, index: Int, path: [AXMenuStep]) async -> Bool {
        guard !isOwn(pid) else { return false }
        return await run {
            guard let item = statusItem(pid: pid, index: index) else { return false }
            return press(from: item, rest: path)
        }
    }

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

    private static func submenu(of item: AXUIElement) -> AXUIElement? {
        AX.elements(item, kAXChildrenAttribute).first { AX.string($0, kAXRoleAttribute) == kAXMenuRole as String }
    }

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

@MainActor
enum AXMenuEntries {
    static func entries(_ nodes: [AppMenuNode], press: @escaping @MainActor ([AXMenuStep]) -> Void) -> [ElementMenuEntry] {
        nodes.map { node in
            if node.isSeparator { return .separator }
            if node.hasSubmenu { return .submenu(node.title, entries(node.children, press: press)) }
            let path = node.path
            return .item(ElementMenuCommand(
                title: node.title, checked: node.mark == .check, disabled: !node.enabled, alternate: node.isAlternate,
                mixed: node.mark == .mixed, keyEquivalent: node.shortcut?.keyEquivalent ?? "", keyModifiers: flags(node.modifiers),
                perform: { press(path) }
            ))
        }
    }

    static func flags(_ modifiers: MenuModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }

    static func permission() -> [ElementMenuEntry] {
        [.item(ElementMenuCommand(title: "Allow Accessibility Access to Show Menus…", perform: {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }))]
    }
}
