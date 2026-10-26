import AppKit
import ApolloShellCore
import SwiftUI

/// Baut aus dem gespiegelten Dock-Menue einer App ein NSMenu.
///
/// Gemeinsam genutzt von der Leiste (Dock) und vom Launcher, damit ein
/// Rechtsklick an beiden Stellen dasselbe zeigt.
@MainActor
enum NativeAppMenu {
    /// - Parameter rebind: Bekommt den Titel eines Eintrags und darf ihn
    ///   uebernehmen (etwa "Keep in Dock", das auf unser Dock zeigen
    ///   soll statt auf Apples). `nil` heisst: so lassen, wie Apple es meint.
    static func menu(from nodes: [DockMenuNode], bundleID: String,
                     rebind: (DockMenuNode) -> (state: NSControl.StateValue, enabled: Bool, action: () -> Void)? = { _ in nil }) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        append(nodes, to: menu, bundleID: bundleID, rebind: rebind)
        return menu
    }

    /// Dieselben Eintraege an ein vorhandenes Menue haengen - der Launcher
    /// setzt eigene Zeilen davor und dahinter.
    ///
    /// Anhaengen statt kopieren: Ein NSMenuItem gehoert immer nur in ein
    /// Menue, und `copy()` auf einem `ClosureMenuItem` ginge ueber
    /// `init(coder:)`, den es nicht gibt.
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

    /// Neben dem Symbol, oben buendig: rechts davon, ausser die Leiste steht
    /// rechts - dann links davon. Im Launcher steht das Menue rechts neben
    /// der Zeile.
    static func popUp(_ menu: NSMenu, at view: NSView) {
        // Die Aufrufer warten zuerst auf Apples Dock; bis dahin kann die Zeile
        // weg sein (Hover vorbei, Dock neu gebaut). AppKit wirft dann "View is
        // not in any window" - in einem Swift-Task laesst das die Concurrency-
        // Laufzeit kaputt zurueck, und die naechste MainActor-Pruefung stuerzt
        // an ganz anderer Stelle ab.
        guard view.window != nil else { return }
        let top = view.isFlipped ? view.bounds.minY : view.bounds.maxY
        menu.popUp(positioning: nil, at: NSPoint(x: besideX(menu, view, gap: 6), y: top), in: view)
    }

    /// Linke Kante des Menues neben `view`, auf der Seite weg von der Leiste.
    static func besideX(_ menu: NSMenu, _ view: NSView, gap: CGFloat = 0) -> CGFloat {
        guard view.window is SidebarPanel, Sidebar.side == .right else { return view.bounds.maxX + gap }
        return view.bounds.minX - gap - menu.size.width
    }
}

/// Faengt den Rechtsklick auf eine SwiftUI-Zeile ab und gibt die Ansicht
/// weiter, an der das Menue aufgehen soll.
///
/// Warum nicht `contextMenu`: Dessen Inhalt muss sofort feststehen. Das
/// Menue der App kommt aber von Apples Dock und braucht einen Moment - der
/// Rechtsklick muss also erst warten und das Menue dann selbst oeffnen.
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

        // Die Zeile darunter bleibt anklickbar; nur der Rechtsklick landet hier.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp: return super.hitTest(point)
            default: return nil
            }
        }
    }
}
