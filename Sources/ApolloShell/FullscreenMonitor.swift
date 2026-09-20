import AppKit
import ApolloShellCore
import os

/// Notices which screens have a full-screen app on them right now. The bar
/// steps aside there, and the edges open nothing.
///
/// A panel with `.canJoinAllSpaces` appears in full-screen spaces on macOS 26
/// too (those are spaces as well), with or without `.fullScreenAuxiliary`. So
/// it is looked up per screen whether its active space is a full-screen app
/// (`SpaceList.fullscreenDisplays`).
///
/// What is asked is the space, not the foreground app: a full-screen video on
/// one screen stays full screen while a window has the focus on the other.
/// Needs no permission.
@MainActor
final class FullscreenMonitor {
    /// Full screen on and off and space changes are animated; the active space
    /// may only be right afterwards. So it looks once right away (so that the
    /// bar disappears as quickly as possible) and once more after the
    /// animation.
    static let checks: [TimeInterval] = [0.05, 0.4, 1.0]

    private let reader = SpaceReader()
    private let onChange: (Set<CGDirectDisplayID>) -> Void
    private var fullscreen: Set<CGDirectDisplayID> = []
    private var pending: [DispatchWorkItem] = []
    private let log = Logger(category: "fullscreen")

    /// `onChange` gets the screens that are in full screen - on every change,
    /// never twice.
    init(onChange: @escaping (Set<CGDirectDisplayID>) -> Void) {
        self.onChange = onChange
        guard reader != nil else {
            log.error("SkyLight functions for Spaces missing, bar stays visible in full screen")
            return
        }
        observeSystem()
        scheduleChecks()
    }

    /// Lives as long as the process (AppDelegate holds it); the observers hold
    /// it only weakly and are never removed.
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

    /// Not readable or no screen there right now: the old state stays.
    private func refresh() {
        guard let reader, let identifiers = SpaceList.fullscreenDisplays(reader.displays()) else { return }
        let screens = ShellScreens.current()
        guard !screens.isEmpty else { return }
        let next: Set<CGDirectDisplayID>
        if identifiers.contains(SpaceList.sharedDisplayIdentifier.uppercased()) {
            // Shared spaces: one full-screen space holds for all of them.
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
        log.notice("Full screen on \(next.count, privacy: .public) screen(s)")
        onChange(next)
    }
}
