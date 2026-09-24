import AppKit
import ColorSync
import ApolloShellCore

struct ShellScreen: Identifiable {
    let displayID: CGDirectDisplayID
    let screen: NSScreen
    let info: ScreenInfo

    var id: CGDirectDisplayID { displayID }
    var frame: NSRect { screen.frame }
    var visibleFrame: NSRect { screen.visibleFrame }
}

@MainActor
enum ShellScreens {
    static func current() -> [ShellScreen] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        return screens.compactMap { screen in
            guard let id = displayID(of: screen) else { return nil }
            return ShellScreen(
                displayID: id,
                screen: screen,
                info: ScreenInfo(name: screen.localizedName, frame: screen.frame, isPrimary: screen === primary)
            )
        }
    }

    static func uuid(of id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    static func targets(for choice: ScreenChoice, among all: [ShellScreen] = current()) -> [ShellScreen] {
        let chosen = ScreenSelection.targets(among: all.map(\.info), choice: choice)
        var remaining = all
        var result: [ShellScreen] = []
        for info in chosen {
            guard let index = remaining.firstIndex(where: { $0.info == info }) else { continue }
            result.append(remaining.remove(at: index))
        }
        return result
    }

    static func at(_ point: NSPoint, among all: [ShellScreen] = current()) -> ShellScreen? {
        guard let info = ScreenSelection.screen(at: point, among: all.map(\.info)) else { return nil }
        return all.first { $0.info == info } ?? all.first
    }

    static func underPointer(among all: [ShellScreen] = current()) -> ShellScreen? {
        at(NSEvent.mouseLocation, among: all)
    }

    static func onChange(_ handler: @escaping @MainActor () -> Void) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

@MainActor
struct ScreenSlots<Item> {
    private(set) var items: [CGDirectDisplayID: Item] = [:]

    @discardableResult
    mutating func distribute(on choice: ScreenChoice,
                             make: (ShellScreen) -> Item,
                             update: (Item, ShellScreen) -> Void,
                             remove: (Item) -> Void) -> [ShellScreen]? {
        let all = ShellScreens.current()
        guard !all.isEmpty else { return nil }
        let wanted = ShellScreens.targets(for: choice, among: all)
        let keep = Set(wanted.map(\.displayID))
        for (id, item) in items where !keep.contains(id) {
            remove(item)
            items[id] = nil
        }
        for screen in wanted {
            let item = items[screen.displayID] ?? make(screen)
            items[screen.displayID] = item
            update(item, screen)
        }
        return wanted
    }

    mutating func removeAll(_ remove: (Item) -> Void) {
        for item in items.values { remove(item) }
        items = [:]
    }
}
