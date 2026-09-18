import AppKit
import ApolloShellCore
import ApplicationServices
import CoreGraphics
import SwiftUI

/// Das Menue eines Dock-Symbols, aufgebaut wie Apples Dock-Menue, damit
/// die Eintraege dort stehen, wo man sie erwartet:
///
///     ✓ Fenster (aller Schreibtische), das vorderste angehakt
///     ─
///     Befehle der App (Neues Fenster, Neues privates Fenster, Einstellungen)
///     ─
///     Optionen ▸ Im Dock behalten ✓ · In <Dateimanager> zeigen
///     ─
///     Alle Fenster einblenden
///     Ausblenden / Einblenden
///     Beenden (⌥: Sofort beenden)
///
/// Reihenfolge und Trenner am 17.09. an Apples Dock abgeglichen (Vivaldi,
/// kitty, ForkLift): Fenster zuerst, mit Haken am vordersten und einem
/// Fenstersymbol je Zeile, dann die Befehle der App, dann Optionen, und nach
/// einem Trenner der Block aus Einblenden, Ausblenden und Beenden.
/// Einstellungen zeigt Apple dort nicht, also zeigen wir sie dort auch
/// nicht (im Launcher schon - dort gibt es kein Vorbild von Apple).
///
/// Beim Oeffnen gebaut, damit Fensterliste, Befehle und Zustand stimmen.
@MainActor
enum DockMenu {
    static func show(for entry: SidebarDockModel.Entry, model: SidebarDockModel, at view: NSView) {
        // Zuerst das echte Menue von Apples Dock: dort stehen die Eintraege,
        // die die App selbst liefert (zuletzt benutzte Dokumente, eigene
        // Befehle) - die kann von aussen niemand erraten. Klappt das nicht
        // (Symbol nicht in Apples Dock, kein Zugriff), bleibt das selbst
        // gebaute Menue darunter.
        Task { @MainActor in
            let nodes = await AppleDockMenu.snapshot(bundleID: entry.bundleID)
            if !nodes.isEmpty {
                NativeAppMenu.popUp(mirrored(nodes, entry: entry, model: model), at: view)
            } else {
                NativeAppMenu.popUp(ownMenu(for: entry, model: model), at: view)
            }
        }
    }

    /// Apples Menue, mit "Im Dock behalten" auf unser Dock umgehaengt: In
    /// Apples Dock anzuheften waere wirkungslos, es ist ausgeblendet, solange
    /// die Shell laeuft.
    private static func mirrored(_ nodes: [DockMenuNode], entry: SidebarDockModel.Entry,
                                 model: SidebarDockModel) -> NSMenu {
        NativeAppMenu.menu(from: nodes, bundleID: entry.bundleID) { node in
            guard DockMenuTree.isKeepInDock(node.title) else { return nil }
            return (state: model.isPinnedInDock(entry) ? .on : .off,
                    enabled: model.canPin(entry),
                    action: { model.togglePin(entry) })
        }
    }

    /// Das selbst gebaute Menue - der Rueckfall, wenn Apples Dock diese App
    /// nicht kennt.
    private static func ownMenu(for entry: SidebarDockModel.Entry, model: SidebarDockModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let app = model.runningApp(entry.bundleID)

        if let app {
            // Alle Schreibtische: vorher nur der aktuelle, Fenster auf
            // anderen Schreibtischen fehlten dann im Menue.
            let windows = DockWindows.list(pid: app.processIdentifier, allSpaces: true)
            // Wie bei Apple: Haken am vordersten Fenster (das erste, das
            // nicht abgelegt ist), Fenstersymbol an jeder Zeile, abgelegte
            // Fenster mit eigenem Symbol.
            let front = windows.firstIndex { !$0.minimized }
            for (index, window) in windows.enumerated() {
                let item = ClosureMenuItem(window.title.isEmpty ? entry.name : window.title) {
                    DockWindows.raise(window, of: app)
                }
                item.state = index == front ? .on : .off
                item.image = window.minimized
                    ? NSImage(systemSymbolName: "minus.circle", accessibilityDescription: String(localized: "Im Dock"))
                    : NSImage(systemSymbolName: "macwindow", accessibilityDescription: String(localized: "Fenster"))
                menu.addItem(item)
            }
            if !windows.isEmpty { menu.addItem(.separator()) }

            // Nur die Befehle, die Apples Dock auch zeigt.
            let commands = DockAppCommands.commands(pid: app.processIdentifier).filter { $0.kind == .newItem }
            for command in commands {
                menu.addItem(ClosureMenuItem(command.title) { DockAppCommands.press(command, of: app) })
            }
            if !commands.isEmpty { menu.addItem(.separator()) }
        } else {
            menu.addItem(ClosureMenuItem(String(localized: "Öffnen")) { model.click(entry, modifiers: []) })
            menu.addItem(.separator())
        }

        let options = NSMenuItem(title: String(localized: "Optionen"), action: nil, keyEquivalent: "")
        let optionsMenu = NSMenu()
        optionsMenu.autoenablesItems = false
        if model.canPin(entry) {
            let keep = ClosureMenuItem(String(localized: "Im Dock behalten")) { model.togglePin(entry) }
            keep.state = model.isPinnedInDock(entry) ? .on : .off
            optionsMenu.addItem(keep)
        }
        optionsMenu.addItem(ClosureMenuItem(String(localized: "In \(model.fileManagerName) zeigen")) { model.reveal(entry) })
        options.submenu = optionsMenu
        menu.addItem(options)

        if let app {
            // Trenner nach den Optionen, dann der Block wie bei Apple:
            // Einblenden, Aus-/Einblenden, Beenden - ohne Trenner dazwischen.
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(String(localized: "Alle Fenster einblenden")) { SpaceSwitcher.showAppWindows(of: app) })
            menu.addItem(ClosureMenuItem(app.isHidden ? String(localized: "Einblenden") : String(localized: "Ausblenden")) {
                // Ergebnis egal: scheitert es, bleibt die App, wie sie war.
                _ = app.isHidden ? app.unhide() : app.hide()
            })
            menu.addItem(ClosureMenuItem(String(localized: "Beenden")) { app.terminate() })
            // Wie bei Apple: mit gedrueckter ⌥-Taste wird daraus "Sofort beenden".
            let force = ClosureMenuItem(String(localized: "Sofort beenden")) { app.forceTerminate() }
            force.isAlternate = true
            force.keyEquivalentModifierMask = .option
            menu.addItem(force)
        }

        return menu
    }
}

/// Menuepunkt mit Block statt Ziel/Aktion.
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
