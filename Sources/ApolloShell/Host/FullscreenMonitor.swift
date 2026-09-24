import AppKit
import ApolloShellCore

@MainActor
final class FullscreenMonitor {
    static let checks: [TimeInterval] = [0.05, 0.4, 1.0]

    private let read: @MainActor () -> Set<String>?
    private let schedule: @MainActor (TimeInterval, DispatchWorkItem) -> Void
    var apply: @MainActor (Bool, String) -> Void = { _, _ in }
    private(set) var fullscreen: Set<String> = []
    private(set) var checksRun = 0
    private var screens: Set<String> = []
    private var pending: [DispatchWorkItem] = []
    private var observers: [NSObjectProtocol] = []

    init(read: @escaping @MainActor () -> Set<String>?, schedule: @escaping @MainActor (TimeInterval, DispatchWorkItem) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }) {
        self.read = read
        self.schedule = schedule
    }

    static func live() -> FullscreenMonitor {
        let reader = SpaceReader()
        return FullscreenMonitor(read: { reader.flatMap(fullscreenScreens) })
    }

    func contains(_ screenKey: String) -> Bool { fullscreen.contains(screenKey) }

    func setScreens(_ keys: [String]) {
        screens = Set(keys)
        fullscreen.formIntersection(screens)
        poke()
    }

    func poke() {
        for work in pending { work.cancel() }
        pending = Self.checks.map { delay in
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.check() }
            }
            schedule(delay, work)
            return work
        }
    }

    func check() {
        checksRun += 1
        guard let found = read() else { return }
        let next = found.intersection(screens)
        guard next != fullscreen else { return }
        let previous = fullscreen
        fullscreen = next
        for key in screens.sorted() where next.contains(key) != previous.contains(key) {
            apply(next.contains(key), key)
        }
    }

    func observe(_ center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        stop(center)
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.poke() }
            })
        }
    }

    func stop(_ center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
        for work in pending { work.cancel() }
        pending.removeAll()
    }

    private static func fullscreenScreens(_ reader: SpaceReader) -> Set<String>? {
        guard let identifiers = SpaceList.fullscreenDisplays(reader.displays()) else { return nil }
        let screens = ShellScreens.current()
        if identifiers.contains(SpaceList.sharedDisplayIdentifier.uppercased()) {
            return Set(screens.map(\.info.key))
        }
        return Set(screens.filter { screen in
            ShellScreens.uuid(of: screen.displayID).map { identifiers.contains($0.uppercased()) } ?? false
        }.map(\.info.key))
    }
}
