import AppKit
import ApolloShellCore

@MainActor
final class CommandCenter: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let nexus: Nexus
    private let updates: UpdateController
    private let autostart: OnboardingAutostartModel
    private let themes: ThemeStore?

    init(nexus: Nexus, updates: UpdateController, autostart: OnboardingAutostartModel, themes: ThemeStore?) {
        self.nexus = nexus
        self.updates = updates
        self.autostart = autostart
        self.themes = themes
        super.init()
        item.button?.image = ApolloMarkGeometry.menuBarImage(side: 18)
        item.button?.toolTip = "ApolloShell"
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
    }

    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        for i in make() { m.addItem(i) }
    }

    func popUpUnderPointer() {
        let m = NSMenu()
        m.autoenablesItems = false
        for i in make() { m.addItem(i) }
        m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func make() -> [NSMenuItem] {
        autostart.refresh()
        var r: [NSMenuItem] = []
        r.append(Self.item(String(localized: "Settings…"), key: ",") { [nexus] in nexus.show() })
        r.append(Self.item(String(localized: "Edit Bar…")) { [nexus] in nexus.show(page: .bar) })
        r.append(Self.item(String(localized: "Themes…")) { [nexus] in nexus.show(page: .themes) })
        if let themes {
            r.append(Self.item(String(localized: "Marketplace…")) { MarketplaceWindow.shared.show(themes: themes) })
        }
        r.append(.separator())
        r.append(Self.item(String(localized: "Check for Updates…")) { [nexus, updates] in
            updates.checkNow()
            nexus.show(page: .about)
        })
        let login = Self.item(String(localized: "Start at Login")) { [autostart] in autostart.setEnabled(!autostart.state.isOn) }
        login.state = autostart.state.isOn ? .on : .off
        login.isEnabled = autostart.state.canToggle
        r.append(login)
        r.append(.separator())
        r.append(Self.item(String(localized: "About ApolloShell")) { [nexus] in nexus.show(page: .about) })
        r.append(Self.item(String(localized: "Restart ApolloShell")) { Self.restart() })
        r.append(Self.item(String(localized: "Quit ApolloShell"), key: "q") { NSApp.terminate(nil) })
        return r
    }

    private static func restart() {
        AppRestartModel().restart()
    }

    private static func item(_ title: String, key: String = "", _ run: @escaping @MainActor () -> Void) -> NSMenuItem {
        let i = DockSmartMenu.Item(title, run)
        i.keyEquivalent = key
        return i
    }
}
