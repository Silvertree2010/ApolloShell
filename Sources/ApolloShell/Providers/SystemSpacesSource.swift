import AppKit
import ApolloProviders
import ApolloShellCore

@MainActor
final class SystemSpacesSource: SpacesSource {
    private let reader = SpaceReader()
    private var observers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?

    var available: Bool { reader != nil }

    var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    var mainScreen: String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    func read() -> [DisplaySpaces] {
        guard let reader else { return [] }
        return reader.displays().compactMap(Self.display)
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        stopObserving()
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            })
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    func stopObserving() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    func step(right: Bool) {
        SpaceSwitcher.step(right ? 1 : -1)
    }

    func missionControl() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Mission Control.app"), configuration: NSWorkspace.OpenConfiguration())
    }

    private static func display(_ raw: [String: Any]) -> DisplaySpaces? {
        guard let screen = raw["Display Identifier"] as? String, let spaces = raw["Spaces"] as? [[String: Any]] else { return nil }
        let entries = spaces.compactMap { space -> SpaceEntry? in
            guard let type = (space["type"] as? NSNumber)?.intValue,
                  type == SpaceList.desktopType || type == SpaceList.fullscreenType,
                  let id = spaceID(space)
            else { return nil }
            return SpaceEntry(id: id, fullscreen: type == SpaceList.fullscreenType)
        }
        let active = (raw["Current Space"] as? [String: Any]).flatMap(spaceID)
        return DisplaySpaces(screen: screen, spaces: entries, activeID: active)
    }

    private static func spaceID(_ space: [String: Any]) -> UInt64? {
        ((space["id64"] ?? space["ManagedSpaceID"]) as? NSNumber)?.uint64Value
    }
}

struct SpaceReader {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let allSpacesMask: Int32 = 7

    private let connection: Int32
    private let copyDisplaySpaces: CopyDisplaySpaces
    private let copySpacesForWindows: CopySpacesForWindows?

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let connect = Self.symbol(handle, "CGSMainConnectionID", "SLSMainConnectionID"),
              let copy = Self.symbol(handle, "CGSCopyManagedDisplaySpaces", "SLSCopyManagedDisplaySpaces")
        else { return nil }
        connection = unsafeBitCast(connect, to: MainConnection.self)()
        copyDisplaySpaces = unsafeBitCast(copy, to: CopyDisplaySpaces.self)
        copySpacesForWindows = Self.symbol(handle, "CGSCopySpacesForWindows", "SLSCopySpacesForWindows")
            .map { unsafeBitCast($0, to: CopySpacesForWindows.self) }
    }

    func isOnAnySpace(_ window: CGWindowID) -> Bool? {
        guard let copySpacesForWindows,
              let spaces = copySpacesForWindows(connection, Self.allSpacesMask, [window] as CFArray)?
                  .takeRetainedValue() as? [Any]
        else { return nil }
        return !spaces.isEmpty
    }

    func displays() -> [[String: Any]] {
        (copyDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]]) ?? []
    }

    private static func symbol(_ handle: UnsafeMutableRawPointer, _ names: String...) -> UnsafeMutableRawPointer? {
        for name in names {
            if let pointer = dlsym(handle, name) { return pointer }
        }
        return nil
    }
}
