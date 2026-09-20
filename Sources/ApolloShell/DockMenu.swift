import AppKit
import ApolloShellCore
import ApplicationServices
import CoreGraphics
import SwiftUI

/// The menu of a Dock symbol, built like Apple's Dock menu, so that the
/// entries stand where one expects them:
///
///     ✓ windows (of all desktops), the frontmost one ticked
///     ─
///     commands of the app (New Window, New Private Window, Settings)
///     ─
///     Options ▸ Keep in Dock ✓ · Show in <file manager>
///     ─
///     Show All Windows
///     Hide / Show
///     Quit (⌥: Force Quit)
///
/// The order and the separators were matched against Apple's Dock on 17.09.
/// (Vivaldi, kitty, ForkLift): the windows first, with a tick on the frontmost
/// one and a window symbol on every line, then the commands of the app, then
/// the options, and after a separator the block of show, hide and quit. Apple
/// does not show Settings there, so we do not show it there either (in the
/// launcher we do - there is no model from Apple for that).
///
/// Built on opening, so that the window list, the commands and the state are right.
@MainActor
enum DockMenu {
    static func show(for entry: SidebarDockModel.Entry, model: SidebarDockModel, at view: NSView) {
        // The real menu of Apple's Dock first: that is where the entries the
        // app delivers itself stand (recent documents, commands of its own) -
        // nobody can guess those from outside. When that does not work (the
        // symbol is not in Apple's Dock, no access), the menu we build
        // ourselves stays below.
        Task { @MainActor in
            let nodes = await AppleDockMenu.snapshot(bundleID: entry.bundleID)
            if !nodes.isEmpty {
                NativeAppMenu.popUp(mirrored(nodes, entry: entry, model: model), at: view)
            } else {
                NativeAppMenu.popUp(ownMenu(for: entry, model: model), at: view)
            }
        }
    }

    /// Apple's menu, with "Keep in Dock" hooked over to our Dock: pinning in
    /// Apple's Dock would have no effect, since it is hidden while the shell
    /// runs.
    private static func mirrored(_ nodes: [DockMenuNode], entry: SidebarDockModel.Entry,
                                 model: SidebarDockModel) -> NSMenu {
        NativeAppMenu.menu(from: nodes, bundleID: entry.bundleID) { node in
            guard DockMenuTree.isKeepInDock(node.title) else { return nil }
            return (state: model.isPinnedInDock(entry) ? .on : .off,
                    enabled: model.canPin(entry),
                    action: { model.togglePin(entry) })
        }
    }

    /// The menu we build ourselves - the fallback when Apple's Dock does not
    /// know this app.
    private static func ownMenu(for entry: SidebarDockModel.Entry, model: SidebarDockModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let app = model.runningApp(entry.bundleID)

        if let app {
            // All desktops: before, only the current one, and windows on other
            // desktops were then missing from the menu.
            let windows = DockWindows.list(pid: app.processIdentifier, allSpaces: true)
            // As with Apple: a tick on the frontmost window (the first one
            // that is not put away), a window symbol on every line, and put-away
            // windows with a symbol of their own.
            let front = windows.firstIndex { !$0.minimized }
            for (index, window) in windows.enumerated() {
                let item = ClosureMenuItem(window.title.isEmpty ? entry.name : window.title) {
                    DockWindows.raise(window, of: app)
                }
                item.state = index == front ? .on : .off
                item.image = window.minimized
                    ? NSImage(systemSymbolName: "minus.circle", accessibilityDescription: String(localized: "In the Dock"))
                    : NSImage(systemSymbolName: "macwindow", accessibilityDescription: String(localized: "Window"))
                menu.addItem(item)
            }
            if !windows.isEmpty { menu.addItem(.separator()) }

            // Only the commands Apple's Dock shows too.
            let commands = DockAppCommands.commands(pid: app.processIdentifier).filter { $0.kind == .newItem }
            for command in commands {
                menu.addItem(ClosureMenuItem(command.title) { DockAppCommands.press(command, of: app) })
            }
            if !commands.isEmpty { menu.addItem(.separator()) }
        } else {
            menu.addItem(ClosureMenuItem(String(localized: "Open")) { model.click(entry, modifiers: []) })
            menu.addItem(.separator())
        }

        let options = NSMenuItem(title: String(localized: "Options"), action: nil, keyEquivalent: "")
        let optionsMenu = NSMenu()
        optionsMenu.autoenablesItems = false
        if model.canPin(entry) {
            let keep = ClosureMenuItem(String(localized: "Keep in Dock")) { model.togglePin(entry) }
            keep.state = model.isPinnedInDock(entry) ? .on : .off
            optionsMenu.addItem(keep)
        }
        optionsMenu.addItem(ClosureMenuItem(String(localized: "Show in \(model.fileManagerName)")) { model.reveal(entry) })
        options.submenu = optionsMenu
        menu.addItem(options)

        if let app {
            // A separator after the options, then the block as with Apple:
            // show, hide/show, quit - without a separator in between.
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(String(localized: "Show All Windows")) { SpaceSwitcher.showAppWindows(of: app) })
            menu.addItem(ClosureMenuItem(app.isHidden ? String(localized: "Show") : String(localized: "Hide")) {
                // The result does not matter: if it fails, the app stays as it was.
                _ = app.isHidden ? app.unhide() : app.hide()
            })
            menu.addItem(ClosureMenuItem(String(localized: "Quit")) { app.terminate() })
            // As with Apple: with ⌥ held down it becomes "Force Quit".
            let force = ClosureMenuItem(String(localized: "Force Quit")) { app.forceTerminate() }
            force.isAlternate = true
            force.keyEquivalentModifierMask = .option
            menu.addItem(force)
        }

        return menu
    }
}

/// A menu item with a block instead of a target/action.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("nicht aus Nib")
    }

    @objc private func run() {
        handler()
    }
}
