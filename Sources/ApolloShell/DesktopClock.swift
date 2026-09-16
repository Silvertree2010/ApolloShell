import AppKit
import ApolloShellCore
import SwiftUI

/// Schreibtisch-Uhr: liegt hinter allen Fenstern auf dem Schreibtisch, unten
/// rechts (Caelestias Standardposition) mit 32 pt Abstand, ueber dem Dock.
/// Klicks gehen durch sie hindurch.
///
/// Auf jedem Bildschirm, der auch eine Leiste hat (Nexus > Leiste,
/// "Bildschirme") - eine Uhr auf einem Bildschirm ohne Leiste waere ein
/// einzelnes schwebendes Stueck Shell.
///
/// Nexus > Schreibtisch schaltet sie ein und aus, sofort: `Observations`
/// meldet jede Aenderung der Einstellung. Aus heisst Fenster weg UND Timer
/// aus - eine unsichtbare Uhr soll nicht jede Minute neu rechnen. Die Uhrzeit
/// selbst ist ein geteiltes Modell mit einem Timer fuer alle Bildschirme.
@MainActor
final class DesktopClock {
    /// Caelestia: Tokens.padding.extraLargeIncreased.
    private static let margin: CGFloat = 32

    private let model = DesktopClockModel()
    private let settings: ShellSettingsStore
    /// Ein Fenster je Bildschirm, nach Display-Kennung.
    private var windows: [CGDirectDisplayID: DesktopClockWindow] = [:]
    private var timer: Timer?
    private var enabled = false
    private var observation: Task<Void, Never>?
    private var choiceObservation: Task<Void, Never>?

    init(settings: ShellSettingsStore) {
        self.settings = settings
        setEnabled(settings.settings.background.desktopClock)
        observeSystemChanges()
        // Liefert zuerst den aktuellen Wert, danach jede Aenderung. Die
        // Schleifen leben so lange wie die App (AppDelegate haelt die Uhr).
        observation = Task { [weak self, settings] in
            for await on in Observations({ settings.settings.background.desktopClock }) {
                self?.setEnabled(on)
            }
        }
        // Die Uhr folgt der Bildschirm-Einstellung der Leiste.
        choiceObservation = Task { [weak self, settings] in
            for await _ in Observations({ settings.settings.bar.screens }) {
                self?.rebuild()
            }
        }
    }

    private func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            rebuild()
            scheduleTick()
        } else {
            timer?.invalidate()
            timer = nil
            for window in windows.values { window.tearDown() }
            windows = [:]
        }
    }

    /// Uhren anlegen, vermessen und abraeumen, so wie es die Einstellung und
    /// die angeschlossenen Bildschirme verlangen. Ohne Bildschirme bleibt
    /// alles stehen (Kabel mitten im Umstecken).
    private func rebuild() {
        guard enabled else { return }
        let all = ShellScreens.current()
        guard !all.isEmpty else { return }
        let wanted = ShellScreens.targets(for: settings.settings.bar.screens, among: all)
        let keep = Set(wanted.map(\.displayID))

        for (id, window) in windows where !keep.contains(id) {
            window.tearDown()
            windows[id] = nil
        }
        for screen in wanted {
            let window = windows[screen.displayID] ?? DesktopClockWindow(model: model)
            windows[screen.displayID] = window
            window.layout(on: screen, margin: Self.margin, model: model)
            window.show()
        }
    }

    /// Nur die Rahmen neu setzen (die Breite aendert sich mit dem Text), ohne
    /// die Fenster neu zu verteilen.
    private func relayout() {
        guard enabled else { return }
        let all = ShellScreens.current()
        guard !all.isEmpty else { return }
        for screen in ShellScreens.targets(for: settings.settings.bar.screens, among: all) {
            windows[screen.displayID]?.layout(on: screen, margin: Self.margin, model: model)
        }
    }

    /// Zur naechsten vollen Minute weiterschalten, dann jede Minute. Ein
    /// Timer fuer alle Bildschirme.
    private func scheduleTick() {
        model.now = Date()
        let seconds = Calendar.current.component(.second, from: model.now)
        let untilNextMinute = TimeInterval(60 - seconds) + 0.05
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: untilNextMinute, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.now = Date()
                self.relayout() // Breite kann sich aendern (z. B. "Montag" -> "Donnerstag")
                self.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.model.now = Date()
                        self?.relayout()
                    }
                }
            }
        }
    }

    /// Nach Aufwachen stimmt die Minute nicht mehr; nach Bildschirmwechsel
    /// die Verteilung und die Position nicht.
    private func observeSystemChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Ausgeschaltet: keinen Timer wieder anwerfen.
                guard let self, self.enabled else { return }
                self.scheduleTick()
            }
        }
    }
}

/// Das Uhr-Fenster EINES Bildschirms.
@MainActor
private final class DesktopClockWindow {
    private let window: NSPanel
    private let hosting: NSHostingView<DesktopClockView>

    init(model: DesktopClockModel) {
        hosting = NSHostingView(rootView: DesktopClockView(model: model))
        hosting.sizingOptions = []
        window = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Knapp ueber den Schreibtisch-Symbolen, weit unter normalen Fenstern.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = hosting
    }

    func layout(on screen: ShellScreen, margin: CGFloat, model: DesktopClockModel) {
        // An einer frischen Ansicht messen: `hosting` hat sizingOptions = []
        // und meldet deshalb keine eigene Groesse (fittingSize war 0 x 0,
        // die Uhr unsichtbar - gemessen 14.09.).
        let size = NSHostingView(rootView: DesktopClockView(model: model)).fittingSize
        let visible = screen.visibleFrame
        // Der View bringt 24 pt Schatten-Rand mit; die 32 pt gelten fuer die Schrift.
        let inset = margin - 24
        window.setFrame(NSRect(
            x: visible.maxX - size.width - inset,
            y: visible.minY + inset,
            width: size.width,
            height: size.height
        ), display: true)
    }

    func show() {
        guard !window.isVisible else { return }
        window.orderFrontRegardless()
    }

    func tearDown() {
        window.orderOut(nil)
    }
}
