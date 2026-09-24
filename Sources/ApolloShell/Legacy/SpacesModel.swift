import AppKit
import ColorSync
import ApolloShellCore
import Observation
import os

@MainActor
@Observable
final class SpacesModel {
    private(set) var snapshot: SpaceSnapshot?

    private static let pollInterval: TimeInterval = 5
    private static let settleDelay: TimeInterval = 0.5

    @ObservationIgnored private let reader: SpaceReader?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let log = Logger(category: "spaces")

    init() {
        reader = SpaceReader()
        if reader == nil {
            log.error("SkyLight-Funktionen fuer Spaces fehlen, Kapsel bleibt aus")
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

    init(preview snapshot: SpaceSnapshot?) {
        reader = nil
        self.snapshot = snapshot
    }

    func switchTo(_ index: Int) {
        guard let active = snapshot?.activeIndex else { return }
        SpaceSwitcher.step(index - active)
    }

    private func refresh() {
        guard let reader else { return }
        let next = SpaceList.snapshot(displays: reader.displays(), mainDisplay: Self.mainDisplayUUID())
        if next != snapshot { snapshot = next }
    }

    private static func mainDisplayUUID() -> String? {
        ShellScreens.uuid(of: CGMainDisplayID())
    }

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
