import AppKit
import ApolloShellCore
import ApplicationServices
import os

enum AppleDockMenu {
    private static let log = Logger(category: "dockmenu")

    static func snapshot(bundleID: String) async -> [DockMenuNode] {
        await onReaderQueue { read(bundleID: bundleID) }
    }

    private static func read(bundleID: String) -> [DockMenuNode] {
        guard let item = dockItem(bundleID: bundleID) else {
            log.notice("kein Dock-Symbol fuer \(bundleID, privacy: .public)")
            return []
        }
        guard AXUIElementPerformAction(item, kAXShowMenuAction as CFString) == .success else {
            log.notice("AXShowMenu abgelehnt fuer \(bundleID, privacy: .public)")
            return []
        }
        defer { dismiss(item) }
        guard let menu = openMenu(of: item) else {
            log.notice("kein Menue nach AXShowMenu fuer \(bundleID, privacy: .public)")
            return []
        }
        let items = DockMenuTree.nodes(from: read(menu, depth: 0))
        log.notice("Apples Dock-Menue fuer \(bundleID, privacy: .public): \(items.count) Eintraege")
        return items
    }

    static func press(path: [DockMenuStep], bundleID: String) async -> Bool {
        await onReaderQueue { perform(path: path, bundleID: bundleID) }
    }

    private static let queue = DispatchQueue(label: "io.github.silvertree2010.apolloshell.dockmenu",
                                             qos: .userInitiated)

    private static func onReaderQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    private static func perform(path: [DockMenuStep], bundleID: String) -> Bool {
        guard !path.isEmpty, let item = dockItem(bundleID: bundleID),
              AXUIElementPerformAction(item, kAXShowMenuAction as CFString) == .success
        else { return false }
        guard let menu = openMenu(of: item) else {
            dismiss(item)
            return false
        }
        var current = menu
        for (index, step) in path.enumerated() {
            let children = AX.elements(current, kAXChildrenAttribute)
            let atIndex = children.indices.contains(step.index) ? children[step.index] : nil
            let match = (atIndex.flatMap { AX.string($0, kAXTitleAttribute) == step.title ? $0 : nil })
                ?? children.first { AX.string($0, kAXTitleAttribute) == step.title }
            guard let match else {
                dismiss(item)
                return false
            }
            if index == path.count - 1 {
                let pressed = AXUIElementPerformAction(match, kAXPressAction as CFString) == .success
                if !pressed { dismiss(item) }
                return pressed
            }
            guard let submenu = AX.elements(match, kAXChildrenAttribute).first else {
                dismiss(item)
                return false
            }
            current = submenu
        }
        dismiss(item)
        return false
    }

    private static func read(_ menu: AXUIElement, depth: Int) -> [RawMenuItem] {
        guard depth < DockMenuTree.maximumDepth else { return [] }
        let children = AX.elements(menu, kAXChildrenAttribute)
        return children.map { child in
            let submenu = AX.elements(child, kAXChildrenAttribute).first
            return RawMenuItem(
                title: AX.string(child, kAXTitleAttribute) ?? "",
                enabled: (AX.copy(child, kAXEnabledAttribute) as? NSNumber)?.boolValue ?? true,
                mark: AX.string(child, kAXMenuItemMarkCharAttribute) ?? "",
                hasSubmenu: submenu != nil,
                children: submenu.map { read($0, depth: depth + 1) } ?? []
            )
        }
    }

    private static func openMenu(of item: AXUIElement) -> AXUIElement? {
        for _ in 0..<20 {
            let children = AX.elements(item, kAXChildrenAttribute)
            if let menu = children.first(where: { AX.string($0, kAXRoleAttribute) == kAXMenuRole as String }) {
                return menu
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }

    private static func dismiss(_ item: AXUIElement) {
        let children = AX.elements(item, kAXChildrenAttribute)
        for child in children where AX.string(child, kAXRoleAttribute) == kAXMenuRole as String {
            AXUIElementPerformAction(child, kAXCancelAction as CFString)
        }
    }

    private static func dockItem(bundleID: String) -> AXUIElement? {
        AppleDockItems.all(timeout: 0.5).first { AppleDockItems.bundleID(of: $0) == bundleID }
    }
}
