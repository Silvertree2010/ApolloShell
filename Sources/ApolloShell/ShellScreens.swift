import AppKit
import ColorSync
import ApolloShellCore

/// A connected screen the way the shell uses it: the description for the
/// selection (ApolloShellCore/ScreenSelection), the NSScreen that goes with
/// it and the display id.
///
/// Two keys that must not be mixed up:
/// - `info.key` (name plus resolution) is what a SETTING remembers a screen
///   by across replugging. Two identical screens have the same one.
/// - `displayID` says which screen is meant RIGHT NOW. Unambiguous, but macOS
///   hands it out anew when something is plugged in - not something one writes
///   into a file.
///
///
/// So the windows of the shell sit in the catalogue by `displayID`, while the
/// setting talks in terms of `info.key`.
struct ShellScreen: Identifiable {
    let displayID: CGDirectDisplayID
    /// Fetched fresh on every pass: an NSScreen from earlier can report stale
    /// measurements after a replug.
    let screen: NSScreen
    let info: ScreenInfo

    var id: CGDirectDisplayID { displayID }
    var frame: NSRect { screen.frame }
    var visibleFrame: NSRect { screen.visibleFrame }
}

/// Fetch the screens from AppKit and apply the selection out of
/// ApolloShellCore to them.
@MainActor
enum ShellScreens {
    /// All connected screens, the main screen (the one with the menu bar)
    /// first - that is the order of `NSScreen.screens`.
    ///
    /// Empty when none is there right now (a cable in the middle of being
    /// replugged): the callers then leave standing what stands.
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

    /// The UUID of a screen the way SkyLight keeps it in its space list
    /// ("Display Identifier").
    static func uuid(of id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// The screens the bar (and with it the desktop clock and the strip kept
    /// free) should stand on.
    static func targets(for choice: ScreenChoice, among all: [ShellScreen] = current()) -> [ShellScreen] {
        let chosen = ScreenSelection.targets(among: all.map(\.info), choice: choice)
        // Work back through the place in the list, not through the key: two
        // identical screens have the same key, and in mirroring even the same
        // frame.
        var remaining = all
        var result: [ShellScreen] = []
        for info in chosen {
            guard let index = remaining.firstIndex(where: { $0.info == info }) else { continue }
            result.append(remaining.remove(at: index))
        }
        return result
    }

    /// The screen under a point in screen coordinates.
    static func at(_ point: NSPoint, among all: [ShellScreen] = current()) -> ShellScreen? {
        guard let info = ScreenSelection.screen(at: point, among: all.map(\.info)) else { return nil }
        return all.first { $0.info == info } ?? all.first
    }

    /// The screen the pointer stands on right now. That is where the launcher,
    /// the dashboard, the utilities, the session menu and the toasts open.
    static func underPointer(among all: [ShellScreen] = current()) -> ShellScreen? {
        at(NSEvent.mouseLocation, among: all)
    }

    /// Reports every change to the screens: plugged in, unplugged, a different
    /// resolution or arrangement. The observer lives as long as the process;
    /// whoever creates it therefore only holds it weakly.
    static func onChange(_ handler: @escaping @MainActor () -> Void) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    /// `NSScreenNumber` out of the device description is the CGDirectDisplayID.
    /// When it is missing (which happens with a screen that is just
    /// disappearing), the screen does not count.
    /// The `ShellScreen` for an `NSScreen` - through the display id, not
    /// through `==`: AppKit creates `NSScreen` objects anew on changes, and one
    /// fetched earlier (`window.screen`, say) is then no longer the same object
    /// as in `NSScreen.screens`.
    static func matching(_ screen: NSScreen) -> ShellScreen? {
        guard let id = displayID(of: screen) else { return nil }
        return current().first { $0.displayID == id }
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// One entry per screen, by display id: create, refresh, clear away - the way
/// the setting and the connected screens ask for right now. The bar and the
/// desktop clock spread themselves out with it.
@MainActor
struct ScreenSlots<Item> {
    private(set) var items: [CGDirectDisplayID: Item] = [:]

    /// Spread them anew. `make` creates one for a new screen, `update` runs
    /// afterwards for EVERY wanted one (new or there already), `remove` for
    /// every one that is gone or deselected.
    ///
    /// Without screens (a cable in the middle of being replugged,
    /// `NSScreen.screens` empty) everything stays standing instead of being
    /// torn down and built up again at once: then `nil`. When they come back,
    /// `onChange` reports it. Otherwise the screens that have an entry now.
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

    /// Clear everything away (switched off, say).
    mutating func removeAll(_ remove: (Item) -> Void) {
        for item in items.values { remove(item) }
        items = [:]
    }
}
