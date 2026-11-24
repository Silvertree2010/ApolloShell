import AppKit
import ApolloShellCore
import os

/// Merkt, auf welchen Bildschirmen gerade eine Vollbild-App steht. Dort
/// tritt die Leiste ab, und die Kanten oeffnen nichts.
///
/// Ein Panel mit `.canJoinAllSpaces` erscheint auf macOS 26 auch in
/// Vollbild-Spaces (die sind auch nur Spaces), egal ob mit oder ohne
/// `.fullScreenAuxiliary`. Deshalb wird je Bildschirm nachgesehen, ob sein
/// aktiver Space eine Vollbild-App ist (`SpaceList.fullscreenDisplays`).
///
/// Gefragt wird der Space, nicht die Vordergrund-App: ein Vollbild-Video
/// auf dem einen Bildschirm bleibt Vollbild, waehrend auf dem anderen ein
/// Fenster den Fokus hat. Braucht keine Freigabe.
///
/// Spiele und manche Player legen keinen Vollbild-Space an, sondern ein
/// randloses Fenster in Bildschirmgroesse oder nehmen den Bildschirm
/// exklusiv. Das zeigt nur die Fensterliste (`ScreenCover`); weil dabei
/// keine Meldung kommt, wird sie jede Sekunde gelesen (gemessen 0,26 ms).
@MainActor
final class FullscreenMonitor {
    /// Vollbild an/aus und Space-Wechsel sind animiert; der aktive Space
    /// stimmt womoeglich erst danach. Deshalb gleich einmal (damit die
    /// Leiste moeglichst schnell verschwindet) und nach der Animation noch
    /// einmal.
    static let checks: [TimeInterval] = [0.05, 0.4, 1.0]
    static let coverInterval: TimeInterval = 1

    private let reader = SpaceReader()
    private let onChange: (Set<CGDirectDisplayID>) -> Void
    private var fullscreen: Set<CGDirectDisplayID> = []
    private var pending: [DispatchWorkItem] = []
    private var spaces: Set<CGDirectDisplayID> = []
    private var timer: Timer?
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let log = Logger(category: "fullscreen")

    /// `onChange` bekommt die Bildschirme, auf denen Vollbild ist - bei
    /// jeder Aenderung, nie doppelt.
    init(onChange: @escaping (Set<CGDirectDisplayID>) -> Void) {
        self.onChange = onChange
        if reader == nil {
            log.error("SkyLight-Funktionen fuer Spaces fehlen, nur randloses Vollbild wird erkannt")
        }
        observeSystem()
        scheduleChecks()
        let timer = Timer(timeInterval: Self.coverInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(spaces: false) }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Lebt so lange wie der Prozess (AppDelegate haelt ihn); die
    /// Beobachter halten ihn nur schwach und werden nie entfernt.
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
                MainActor.assumeIsolated { self?.refresh(spaces: true) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    /// Nicht lesbar oder gerade kein Bildschirm da: der alte Stand bleibt.
    private func refresh(spaces readSpaces: Bool) {
        let screens = ShellScreens.current()
        guard !screens.isEmpty else { return }
        if readSpaces, let next = fullscreenSpaces(screens) { spaces = next }
        let next = spaces.union(coveredScreens(screens))
        guard next != fullscreen else { return }
        fullscreen = next
        log.notice("Vollbild auf \(next.count, privacy: .public) Bildschirm(en)")
        onChange(next)
    }

    private func coveredScreens(_ screens: [ShellScreen]) -> Set<CGDirectDisplayID> {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        guard let list = list as? [[String: Any]] else { return [] }
        return ScreenCover.coveredScreens(
            windows: ScreenCover.windows(list),
            screens: screens.map { .init(id: $0.displayID, frame: CGDisplayBounds($0.displayID)) },
            frontPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            ownPID: ownPID
        )
    }

    private func fullscreenSpaces(_ screens: [ShellScreen]) -> Set<CGDirectDisplayID>? {
        guard let reader, let identifiers = SpaceList.fullscreenDisplays(reader.displays()) else { return nil }
        let next: Set<CGDirectDisplayID>
        if identifiers.contains(SpaceList.sharedDisplayIdentifier.uppercased()) {
            // Gemeinsame Spaces: ein Vollbild-Space gilt fuer alle.
            next = Set(screens.map(\.displayID))
        } else {
            next = Set(screens.compactMap { screen in
                guard let uuid = ShellScreens.uuid(of: screen.displayID),
                      identifiers.contains(uuid.uppercased())
                else { return nil }
                return screen.displayID
            })
        }
        return next
    }
}
