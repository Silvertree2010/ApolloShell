import AppKit
import ApolloProviders
import ApolloShellCore
import os

@MainActor
final class SystemScreensSource: ScreensSource {
    static let checks: [TimeInterval] = [0.05, 0.4, 1.0]

    private let reader = SpaceReader()
    private var fullscreen: Set<CGDirectDisplayID> = []
    private var handler: (@MainActor () -> Void)?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var pending: [DispatchWorkItem] = []
    private let log = Logger(category: "screens")

    func screens() -> [ScreenState] {
        let all = NSScreen.screens
        guard let primary = all.first else { return [] }
        return all.map { screen in
            ScreenState(
                name: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                scale: Double(screen.backingScaleFactor),
                primary: screen === primary,
                notch: screen.safeAreaInsets.top > 0,
                menubarHeight: Double(max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)),
                fullscreen: Self.displayID(of: screen).map(fullscreen.contains) ?? false
            )
        }
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        stopObserving()
        self.handler = handler
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleChecks() }
            })
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handler?()
                self?.scheduleChecks()
            }
        }
        if reader == nil { log.error("SkyLight functions for spaces are missing, fullscreen stays false") }
        scheduleChecks()
    }

    func stopObserving() {
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { workspace.removeObserver(observer) }
        workspaceObservers.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        for work in pending { work.cancel() }
        pending.removeAll()
        handler = nil
    }

    private func scheduleChecks() {
        guard reader != nil else { return }
        for work in pending { work.cancel() }
        pending = Self.checks.map { delay in
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.checkFullscreen() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    private func checkFullscreen() {
        guard let reader, let identifiers = SpaceList.fullscreenDisplays(reader.displays()) else { return }
        let screens = NSScreen.screens.compactMap(Self.displayID)
        guard !screens.isEmpty else { return }
        let next: Set<CGDirectDisplayID>
        if identifiers.contains(SpaceList.sharedDisplayIdentifier.uppercased()) {
            next = Set(screens)
        } else {
            next = Set(screens.filter { id in
                Self.uuid(of: id).map { identifiers.contains($0.uppercased()) } ?? false
            })
        }
        guard next != fullscreen else { return }
        fullscreen = next
        handler?()
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func uuid(of id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
