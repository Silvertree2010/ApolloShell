import AppKit
import ApolloControl
import ApolloShellCore

@MainActor
final class CommandCenterController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var builder: CommandCenterMenu?
    private let entries: @MainActor () -> [MenuEntry]
    private var handoffObserver: NSObjectProtocol?

    init(entries: @escaping @MainActor () -> [MenuEntry], perform: @escaping @MainActor (MenuCommand) -> Void) {
        self.entries = entries
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        builder = CommandCenterMenu { command in MainActor.assumeIsolated { perform(command) } }
        statusItem.button?.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "ApolloShell")
        menu.delegate = self
        statusItem.menu = menu
        handoffObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(SingleInstance.showNotification), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.popUpUnderPointer() }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let builder else { return }
        let fresh = builder.make(entries())
        let items = fresh.items
        fresh.removeAllItems()
        menu.removeAllItems()
        for item in items { menu.addItem(item) }
    }

    func popUpUnderPointer() {
        guard let builder else { return }
        builder.make(entries()).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func remove() {
        if let handoffObserver { DistributedNotificationCenter.default().removeObserver(handoffObserver) }
        handoffObserver = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
