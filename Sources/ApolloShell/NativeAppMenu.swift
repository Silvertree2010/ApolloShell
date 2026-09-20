import AppKit
import ApolloShellCore
import SwiftUI

/// Builds an NSMenu out of the mirrored Dock menu of an app.
///
/// Shared by the bar (the Dock) and the launcher, so that a right click shows
/// the same in both places.
@MainActor
enum NativeAppMenu {
    /// - Parameter rebind: gets the title of an entry and may take it over
    ///   ("Keep in Dock", say, which should point at our Dock instead of
    ///   Apple's). `nil` means: leave it the way Apple means it.
    static func menu(from nodes: [DockMenuNode], bundleID: String,
                     rebind: (DockMenuNode) -> (state: NSControl.StateValue, enabled: Bool, action: () -> Void)? = { _ in nil }) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        append(nodes, to: menu, bundleID: bundleID, rebind: rebind)
        return menu
    }

    /// Hang the same entries on an existing menu - the launcher puts rows of
    /// its own before and after them.
    ///
    /// Appending instead of copying: an NSMenuItem always belongs in only one
    /// menu, and `copy()` on a `ClosureMenuItem` would go through
    /// `init(coder:)`, which does not exist.
    static func append(_ nodes: [DockMenuNode], to menu: NSMenu, bundleID: String,
                       rebind: (DockMenuNode) -> (state: NSControl.StateValue, enabled: Bool, action: () -> Void)? = { _ in nil }) {
        for node in nodes {
            if node.separator {
                menu.addItem(.separator())
                continue
            }
            if !node.children.isEmpty {
                let parent = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
                parent.submenu = self.menu(from: node.children, bundleID: bundleID, rebind: rebind)
                parent.isEnabled = node.enabled
                menu.addItem(parent)
                continue
            }
            let item: NSMenuItem
            if let own = rebind(node) {
                item = ClosureMenuItem(node.title, handler: own.action)
                item.state = own.state
                item.isEnabled = own.enabled
            } else {
                let path = node.path
                item = ClosureMenuItem(node.title) {
                    Task { _ = await AppleDockMenu.press(path: path, bundleID: bundleID) }
                }
                item.state = node.checked ? .on : .off
                item.isEnabled = node.enabled
            }
            menu.addItem(item)
        }
    }

    /// To the right of the symbol, flush at the top - the bar lies on the left,
    /// and in the launcher the menu then stands next to the row.
    static func popUp(_ menu: NSMenu, at view: NSView) {
        let top = view.isFlipped ? view.bounds.minY : view.bounds.maxY
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.maxX + 6, y: top), in: view)
    }
}

/// Catches the right click on a SwiftUI row and hands on the view the menu
/// should open at.
///
/// Why not `contextMenu`: its content has to stand right away. The menu of the
/// app comes out of Apple's Dock though and takes a moment - so the right
/// click has to wait first and then open the menu itself.
struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: @MainActor (NSView) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onRightClick = onRightClick
    }

    final class CatcherView: NSView {
        var onRightClick: (@MainActor (NSView) -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?(self)
        }

        // The row below it stays clickable; only the right click lands here.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp: return super.hitTest(point)
            default: return nil
            }
        }
    }
}
