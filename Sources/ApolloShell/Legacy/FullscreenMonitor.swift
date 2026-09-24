import AppKit
import ApolloShellCore
import os

@MainActor
final class FullscreenMonitor {
    static let checks: [TimeInterval] = [0.05, 0.4, 1.0]

    private let reader = SpaceReader()
    private let onChange: (Set<CGDirectDisplayID>) -> Void
    private var fullscreen: Set<CGDirectDisplayID> = []
    private var pending: [DispatchWorkItem] = []
    private let log = Logger(category: "fullscreen")

    init(onChange: @escaping (Set<CGDirectDisplayID>) -> Void) {
        self.onChange = onChange
        guard reader != nil else {
            log.error("SkyLight-Funktionen fuer Spaces fehlen, Leiste bleibt im Vollbild stehen")
            return
        }
        observeSystem()
        scheduleChecks()
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleChecks() }
            }
        }
        ShellScreens.onChange { [weak self] in self?.scheduleChecks() }
    }

    private func scheduleChecks() {
        for work in pending { work.cancel() }
        pending = Self.checks.map { delay in
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    private func refresh() {
        guard let reader, let identifiers = SpaceList.fullscreenDisplays(reader.displays()) else { return }
        let screens = ShellScreens.current()
        guard !screens.isEmpty else { return }
        let next: Set<CGDirectDisplayID>
        if identifiers.contains(SpaceList.sharedDisplayIdentifier.uppercased()) {
            next = Set(screens.map(\.displayID))
        } else {
            next = Set(screens.compactMap { screen in
                guard let uuid = ShellScreens.uuid(of: screen.displayID),
                      identifiers.contains(uuid.uppercased())
                else { return nil }
                return screen.displayID
            })
        }
        guard next != fullscreen else { return }
        fullscreen = next
        log.notice("Vollbild auf \(next.count, privacy: .public) Bildschirm(en)")
        onChange(next)
    }
}
