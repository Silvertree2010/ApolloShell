import AppKit
import ColorSync
import ApolloShellCore
import Observation
import os

/// The spaces of the main screen for the capsule at the top of the bar
/// (Caelestia: Workspaces).
///
/// macOS has no public interface for that. It is read through SkyLight's
/// `CGSCopyManagedDisplaySpaces` - private, but read-only and without a
/// permission; measured at 0.16 ms per call (14.09.). Switching would only be
/// possible through a simulated key press, so a click on the capsule does
/// nothing.
///
/// The capsule does not tell occupied from empty (Caelestia: bigger dots for
/// spaces with windows): that would need a second private function (windows
/// per space) whose behavior is not measured here. All inactive dots the same
/// rather than wrong entries.
@MainActor
@Observable
final class SpacesModel {
    /// `nil`: not readable - then the bar shows no capsule.
    private(set) var snapshot: SpaceSnapshot?

    /// New spaces come about in Mission Control, and there is no notification
    /// for that. Looking every 5 s costs practically nothing at 0.16 ms.
    private static let pollInterval: TimeInterval = 5
    /// Look again after a space change: the notification comes during the
    /// swipe animation (as with the window watch); whether "Current Space" is
    /// right by then is not measured.
    private static let settleDelay: TimeInterval = 0.5

    @ObservationIgnored private let reader: SpaceReader?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let log = Logger(category: "spaces")

    init() {
        reader = SpaceReader()
        if reader == nil {
            log.error("SkyLight functions for Spaces missing, capsule stays off")
            return
        }
        refresh()
        observeSystemChanges()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// For the image sample: fixed values, never calls SkyLight.
    init(preview snapshot: SpaceSnapshot?) {
        reader = nil
        self.snapshot = snapshot
    }

    /// A click on the dot `index`: as many desktops further as it is away from
    /// the active one. Without a known active one (full screen) nothing.
    func switchTo(_ index: Int) {
        guard let active = snapshot?.activeIndex else { return }
        SpaceSwitcher.step(index - active)
    }

    private func refresh() {
        guard let reader else { return }
        let next = SpaceList.snapshot(displays: reader.displays(), mainDisplay: Self.mainDisplayUUID())
        if next != snapshot { snapshot = next }
    }

    /// The UUID of the screen with the menu bar (CGMainDisplayID is the one
    /// with the origin, so the same as NSScreen.screens.first). SkyLight keeps
    /// its spaces under this UUID ("Display Identifier").
    private static func mainDisplayUUID() -> String? {
        ShellScreens.uuid(of: CGMainDisplayID())
    }

    /// Lives as long as the bar and with it the process; the observers hold
    /// the model only weakly and are never removed.
    private func observeSystemChanges() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
                    MainActor.assumeIsolated { self?.refresh() }
                }
            }
        }
        // App switches are frequent and the call is cheap: it usually catches
        // new spaces faster than the 5 s beat.
        for name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        ShellScreens.onChange { [weak self] in self?.refresh() }
    }
}

/// A thin shell around the two private SkyLight functions. Through dlsym
/// instead of linked: when they are missing in a later macOS version, the
/// launcher still starts, only without the spaces capsule. Both names are
/// tried, because Apple is replacing the CGS names with SLS ones step by step
/// (on macOS 26.6 the CGS names are still there, measured 14.09.).
/// `FullscreenMonitor` reads it too.
struct SpaceReader {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    /// All kinds of spaces (current, other, full screen).
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

    /// Does the window lie on any space? `nil` when it cannot be read.
    /// Windows an app only keeps in memory lie on none.
    func isOnAnySpace(_ window: CGWindowID) -> Bool? {
        guard let copySpacesForWindows,
              let spaces = copySpacesForWindows(connection, Self.allSpacesMask, [window] as CFArray)?
                  .takeRetainedValue() as? [Any]
        else { return nil }
        return !spaces.isEmpty
    }

    /// "Copy" in the name: the array belongs to us (retained).
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
