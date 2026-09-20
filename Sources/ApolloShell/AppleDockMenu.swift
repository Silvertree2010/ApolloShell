import AppKit
import ApolloShellCore
import ApplicationServices
import os

/// Reads the Dock menu **Apple's** Dock shows for an app and hands it back as
/// a tree.
///
/// Why this detour: what stands in that menu is delivered by the app itself to
/// the Dock (`applicationDockMenu(_:)`, NSDockTilePlugIn) - recent documents,
/// "New Private Window", whatever it offers. This way is open to Apple's Dock
/// only; from outside there is no interface for it. Entries guessed out of the
/// menu bar are therefore always an approximation.
///
/// What does work: let Apple's Dock build the menu tree and read it through
/// the accessibility API. That way every app gets exactly its own entries,
/// including "Options" with everything Apple puts in there.
///
///
/// Two things are unchecked and are measured on the first run (the log
/// `dockmenu`):
/// - whether `AXShowMenu` carries even when Apple's Dock is hidden
///   (ApolloShell hides it while it runs),
/// - whether something flashes on the screen while it does.
///
/// If it does not carry, the menu we build ourselves (`DockMenu`) stays.
///
/// Everything here runs **off** the main thread: a call to the accessibility
/// API waits for the other app, and Apple's Dock takes its time building a
/// menu. On the main thread that would be a bar standing still on every right
/// click.
enum AppleDockMenu {
    private static let log = Logger(category: "dockmenu")

    /// The menu of an app the way Apple's Dock shows it. Empty when there is
    /// no such symbol there or the menu could not be read.
    static func snapshot(bundleID: String) async -> [DockMenuNode] {
        await onReaderQueue { read(bundleID: bundleID) }
    }

    private static func read(bundleID: String) -> [DockMenuNode] {
        guard let item = dockItem(bundleID: bundleID) else {
            log.notice("no Dock icon for \(bundleID, privacy: .public)")
            return []
        }
        guard AXUIElementPerformAction(item, kAXShowMenuAction as CFString) == .success else {
            log.notice("AXShowMenu rejected for \(bundleID, privacy: .public)")
            return []
        }
        defer { dismiss(item) }
        guard let menu = openMenu(of: item) else {
            log.notice("no menu after AXShowMenu for \(bundleID, privacy: .public)")
            return []
        }
        // Read here, interpret in the core (`DockMenuTree`, checked).
        let items = DockMenuTree.nodes(from: read(menu, depth: 0))
        log.notice("Apple's Dock menu for \(bundleID, privacy: .public): \(items.count) entries")
        return items
    }

    /// Carries out an entry: open Apple's menu once more, walk the way through
    /// the titles, press.
    static func press(path: [DockMenuStep], bundleID: String) async -> Bool {
        await onReaderQueue { perform(path: path, bundleID: bundleID) }
    }

    /// A thread of its own for the accessibility API.
    ///
    /// Not `Task.detached`: the calls wait (up to half a second each) and wait
    /// for Apple's Dock in between. On Swift's shared thread pool that would be
    /// a blocked thread other work needs. A serial queue, so that two quick
    /// right clicks run one after another and do not open two menus at once.
    ///
    /// oeffnen.
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
        // From here on Apple's menu stands open; under no circumstances may it
        // be left standing open.
        guard let menu = openMenu(of: item) else {
            dismiss(item)
            return false
        }
        var current = menu
        for (index, step) in path.enumerated() {
            let children = AX.elements(current, kAXChildrenAttribute)
            // Look at the place the entry stood first, and only search by title
            // when the title there no longer fits (the menu has changed).
            //
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
            // A submenu: its menu hangs as a child of the entry.
            guard let submenu = AX.elements(match, kAXChildrenAttribute).first else {
                dismiss(item)
                return false
            }
            current = submenu
        }
        dismiss(item)
        return false
    }

    // MARK: - Reading

    /// Read raw, interpret nothing: what becomes of it is decided by `DockMenuTree`.
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

    /// The menu that hangs as a child of the symbol after `AXShowMenu`. The
    /// Dock does not build it right away, hence a few short attempts.
    private static func openMenu(of item: AXUIElement) -> AXUIElement? {
        for _ in 0..<20 {
            let children = AX.elements(item, kAXChildrenAttribute)
            if let menu = children.first(where: { AX.string($0, kAXRoleAttribute) == kAXMenuRole as String }) {
                return menu
            }
            // No RunLoop: this runs on a queue of its own.
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }

    /// Close Apple's menu again. Without that it would be left standing open.
    private static func dismiss(_ item: AXUIElement) {
        let children = AX.elements(item, kAXChildrenAttribute)
        for child in children where AX.string(child, kAXRoleAttribute) == kAXMenuRole as String {
            AXUIElementPerformAction(child, kAXCancelAction as CFString)
        }
    }

    /// The symbol of this app in Apple's Dock - found through the AXURL, as
    /// with the badges (`DockBadges`).
    private static func dockItem(bundleID: String) -> AXUIElement? {
        AppleDockItems.all(timeout: 0.5).first { AppleDockItems.bundleID(of: $0) == bundleID }
    }
}
