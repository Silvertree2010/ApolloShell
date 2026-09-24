import AppKit
import ApolloShellCore
import SwiftUI

@MainActor
enum NativeAppMenu {
    static func menu(from nodes: [DockMenuNode], bundleID: String,
                     rebind: (DockMenuNode) -> (state: NSControl.StateValue, enabled: Bool, action: () -> Void)? = { _ in nil }) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        append(nodes, to: menu, bundleID: bundleID, rebind: rebind)
        return menu
    }

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

    static func popUp(_ menu: NSMenu, at view: NSView) {
        guard view.window != nil else { return }
        let top = view.isFlipped ? view.bounds.minY : view.bounds.maxY
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.maxX + 6, y: top), in: view)
    }
}

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

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp: return super.hitTest(point)
            default: return nil
            }
        }
    }
}
