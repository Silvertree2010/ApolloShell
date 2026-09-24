import AppKit
import ApolloConfig
import ApolloControl
import ApolloShellCore

@MainActor
final class CommandCenterMenu: NSObject {
    private final class CommandBox: NSObject {
        let command: MenuCommand

        init(_ command: MenuCommand) {
            self.command = command
        }
    }

    private let perform: (MenuCommand) -> Void

    init(perform: @escaping (MenuCommand) -> Void) {
        self.perform = perform
    }

    func make(_ entries: [MenuEntry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            menu.addItem(item(for: entry))
        }
        return menu
    }

    @objc func choose(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? CommandBox else { return }
        perform(box.command)
    }

    private func item(for entry: MenuEntry) -> NSMenuItem {
        switch entry.kind {
        case .separator:
            return .separator()
        case .header:
            return .sectionHeader(title: entry.title)
        case .item:
            let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
            item.isEnabled = entry.enabled
            item.state = entry.checked ? .on : .off
            if let shortcut = entry.shortcut, let chord = KeyChord.parse(shortcut) {
                item.keyEquivalent = Self.keyEquivalent(chord.key)
                item.keyEquivalentModifierMask = Self.modifierMask(chord.modifiers)
            }
            if let icon = entry.icon {
                item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
            }
            if let children = entry.children {
                item.submenu = make(children)
            } else if let command = entry.command {
                item.target = self
                item.action = #selector(choose(_:))
                item.representedObject = CommandBox(command)
            }
            return item
        }
    }

    static func keyEquivalent(_ key: String) -> String {
        switch key {
        case "space": " "
        case "return", "enter": "\r"
        case "tab": "\t"
        case "escape": "\u{1b}"
        case "delete": "\u{8}"
        default: key.count == 1 ? key : ""
        }
    }

    static func modifierMask(_ modifiers: HotKeyModifiers) -> NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { mask.insert(.command) }
        if modifiers.contains(.shift) { mask.insert(.shift) }
        if modifiers.contains(.option) { mask.insert(.option) }
        if modifiers.contains(.control) { mask.insert(.control) }
        return mask
    }
}
