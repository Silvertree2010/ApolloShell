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
    private var tracking = false

    init(entries: @escaping @MainActor () -> [MenuEntry], perform: @escaping @MainActor (MenuCommand) -> Void) {
        self.entries = entries
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        builder = CommandCenterMenu { command in MainActor.assumeIsolated { perform(command) } }
        statusItem.button?.image = ApolloMarkGeometry.menuBarImage(side: 18)
        menu.delegate = self
        statusItem.menu = menu
        handoffObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(SingleInstance.showNotification), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.popUpUnderPointer() }
        }
        SystemStatusItemsSource.shared.own = { [weak self] in self?.ownItem() }
    }

    func ownItem() -> SystemStatusItemsSource.OwnItem? {
        guard statusItem.isVisible, let button = statusItem.button, let window = button.window, let image = button.image else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return SystemStatusItemsSource.OwnItem(frame: frame, image: image, open: { [weak self] in self?.openBelow() })
    }

    private func openBelow() {
        statusItem.button?.performClick(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        tracking = true
    }

    func menuDidClose(_ menu: NSMenu) {
        tracking = false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let builder, !tracking else { return }
        let fresh = builder.make(entries())
        let items = fresh.items
        fresh.removeAllItems()
        menu.removeAllItems()
        for item in items { menu.addItem(item) }
    }

    var visible: Bool {
        get { statusItem.isVisible }
        set { if statusItem.isVisible != newValue { statusItem.isVisible = newValue } }
    }

    func popUpUnderPointer() {
        guard let builder else { return }
        builder.make(entries()).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func remove() {
        if let handoffObserver { DistributedNotificationCenter.default().removeObserver(handoffObserver) }
        handoffObserver = nil
        SystemStatusItemsSource.shared.own = { nil }
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
