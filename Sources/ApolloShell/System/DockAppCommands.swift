import AppKit
import ApolloShellCore
import ApplicationServices
import CoreGraphics
import SwiftUI

enum DockAppCommands {
    struct Command {
        let title: String
        let kind: DockCommandKind
        let element: AXUIElement
    }

    @MainActor
    static func commands(pid: pid_t) -> [Command] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let barValue = AX.copy(app, kAXMenuBarAttribute),
              CFGetTypeID(barValue) == AXUIElementGetTypeID()
        else { return [] }
        let bar = unsafeDowncast(barValue, to: AXUIElement.self)
        let menus = AX.elements(bar, kAXChildrenAttribute)
        var commands: [Command] = []
        var seen: Set<String> = []
        for index in [1, 2] where menus.count > index {
            guard let menu = AX.elements(menus[index], kAXChildrenAttribute).first else { continue }
            let items = AX.elements(menu, kAXChildrenAttribute)
            for item in items {
                guard let title = AX.string(item, kAXTitleAttribute),
                      (AX.copy(item, kAXEnabledAttribute) as? NSNumber)?.boolValue ?? false,
                      let kind = DockCommandFilter.kind(title: title, shortcut: shortcut(of: item)),
                      seen.insert(title).inserted
                else { continue }
                commands.append(Command(title: title, kind: kind, element: item))
            }
        }
        return commands.filter { $0.kind == .newItem } + commands.filter { $0.kind == .settings }
    }

    @MainActor
    private static func shortcut(of item: AXUIElement) -> MenuShortcut? {
        guard let character = AX.string(item, kAXMenuItemCmdCharAttribute), !character.isEmpty else { return nil }
        let modifiers = (AX.copy(item, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? 0
        return MenuShortcut(character: character, modifiers: modifiers)
    }

    @MainActor
    static func press(_ command: Command, of app: NSRunningApplication) {
        app.activate()
        AXUIElementPerformAction(command.element, kAXPressAction as CFString)
    }
}
