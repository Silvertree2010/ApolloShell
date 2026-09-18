import AppKit
import ColorSync
import ApolloShellCore
import Observation
import os

/// Spaces des Hauptbildschirms fuer die Kapsel oben in der Leiste
/// (Caelestia: Workspaces).
///
/// macOS hat dafuer keine oeffentliche Schnittstelle. Gelesen wird ueber
/// SkyLights `CGSCopyManagedDisplaySpaces` - privat, aber nur lesend und
/// ohne Freigabe; gemessen 0,16 ms pro Aufruf (14.09.). Umschalten koennte
/// man nur per simuliertem Tastendruck, deshalb tut ein Klick auf die
/// Kapsel nichts.
///
/// Belegt/leer unterscheidet die Kapsel nicht (Caelestia: groessere Punkte
/// fuer Spaces mit Fenstern): dafuer braeuchte es eine zweite private
/// Funktion (Fenster je Space), deren Verhalten hier nicht gemessen ist.
/// Lieber alle inaktiven Punkte gleich als falsche Angaben.
@MainActor
@Observable
final class SpacesModel {
    /// `nil`: nicht lesbar - dann zeigt die Leiste keine Kapsel.
    private(set) var snapshot: SpaceSnapshot?

    /// Neue Spaces entstehen in Mission Control, dafuer gibt es keine
    /// Meldung. Alle 5 s nachsehen kostet bei 0,16 ms praktisch nichts.
    private static let pollInterval: TimeInterval = 5
    /// Nach einem Space-Wechsel noch einmal nachsehen: die Meldung kommt
    /// waehrend der Wisch-Animation (so auch bei der Fensterwache); ob
    /// "Current Space" dann schon stimmt, ist nicht gemessen.
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

    /// Fuer die Bildprobe: feste Werte, ruft nie SkyLight auf.
    init(preview snapshot: SpaceSnapshot?) {
        reader = nil
        self.snapshot = snapshot
    }

    /// Klick auf den Punkt `index`: so viele Schreibtische weiter, wie er vom
    /// aktiven entfernt ist. Ohne bekannten aktiven (Vollbild) nichts.
    func switchTo(_ index: Int) {
        guard let active = snapshot?.activeIndex else { return }
        SpaceSwitcher.step(index - active)
    }

    private func refresh() {
        guard let reader else { return }
        let next = SpaceList.snapshot(displays: reader.displays(), mainDisplay: Self.mainDisplayUUID())
        if next != snapshot { snapshot = next }
    }

    /// UUID des Bildschirms mit der Menueleiste (CGMainDisplayID ist der mit
    /// dem Ursprung, also derselbe wie NSScreen.screens.first). Unter dieser
    /// UUID fuehrt SkyLight seine Spaces ("Display Identifier").
    private static func mainDisplayUUID() -> String? {
        ShellScreens.uuid(of: CGMainDisplayID())
    }

    /// Lebt so lange wie die Leiste und damit der Prozess; die Beobachter
    /// halten das Modell nur schwach und werden nie entfernt.
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
        // App-Wechsel sind haeufig und der Aufruf billig: faengt neue Spaces
        // meist schneller als der 5-s-Takt.
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

/// Duenne Huelle um die zwei privaten SkyLight-Funktionen. Per dlsym statt
/// gelinkt: fehlen sie in einer spaeteren macOS-Version, startet der
/// Launcher trotzdem, nur ohne Spaces-Kapsel. Beide Namen probieren, weil
/// Apple die CGS-Namen nach und nach durch SLS ersetzt (auf macOS 26.6
/// gibt es noch die CGS-Namen, gemessen 14.09.). Liest auch
/// `FullscreenMonitor`.
struct SpaceReader {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    /// Alle Arten von Spaces (aktuelle, andere, Vollbild).
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

    /// Liegt das Fenster auf irgendeinem Space? `nil`, wenn nicht lesbar.
    /// Fenster, die eine App nur im Speicher haelt, liegen auf keinem.
    func isOnAnySpace(_ window: CGWindowID) -> Bool? {
        guard let copySpacesForWindows,
              let spaces = copySpacesForWindows(connection, Self.allSpacesMask, [window] as CFArray)?
                  .takeRetainedValue() as? [Any]
        else { return nil }
        return !spaces.isEmpty
    }

    /// "Copy" im Namen: das Array gehoert uns (retained).
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
