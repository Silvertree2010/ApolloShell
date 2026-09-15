import AppKit
import SwiftUI

/// Schreibtisch-Uhr: liegt hinter allen Fenstern auf dem Schreibtisch, unten
/// rechts (Caelestias Standardposition) mit 32 pt Abstand, ueber dem Dock.
/// Klicks gehen durch sie hindurch.
///
/// Nexus > Schreibtisch schaltet sie ein und aus, sofort: `Observations`
/// meldet jede Aenderung der Einstellung. Aus heisst Fenster weg UND Timer
/// aus - eine unsichtbare Uhr soll nicht jede Minute neu rechnen.
@MainActor
final class DesktopClock {
    /// Caelestia: Tokens.padding.extraLargeIncreased.
    private static let margin: CGFloat = 32

    private let model = DesktopClockModel()
    private let window: NSPanel
    private let hosting: NSHostingView<DesktopClockView>
    private var timer: Timer?
    private var enabled = false
    private var observation: Task<Void, Never>?

    init(settings: ShellSettingsStore) {
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

        setEnabled(settings.settings.background.desktopClock)
        observeSystemChanges()
        // Liefert zuerst den aktuellen Wert, danach jede Aenderung. Die
        // Schleife lebt so lange wie die App (AppDelegate haelt die Uhr).
        observation = Task { [weak self, settings] in
            for await on in Observations({ settings.settings.background.desktopClock }) {
                self?.setEnabled(on)
            }
        }
    }

    private func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            layout()
            window.orderFrontRegardless()
            scheduleTick()
        } else {
            timer?.invalidate()
            timer = nil
            window.orderOut(nil)
        }
    }

    private func layout() {
        guard let screen = NSScreen.screens.first else { return }
        // An einer frischen Ansicht messen: `hosting` hat sizingOptions = []
        // und meldet deshalb keine eigene Groesse (fittingSize war 0 x 0,
        // die Uhr unsichtbar - gemessen 14.09.).
        let size = NSHostingView(rootView: DesktopClockView(model: model)).fittingSize
        let visible = screen.visibleFrame
        // Der View bringt 24 pt Schatten-Rand mit; die 32 pt gelten fuer die Schrift.
        let inset = Self.margin - 24
        window.setFrame(NSRect(
            x: visible.maxX - size.width - inset,
            y: visible.minY + inset,
            width: size.width,
            height: size.height
        ), display: true)
    }

    /// Zur naechsten vollen Minute weiterschalten, dann jede Minute.
    private func scheduleTick() {
        model.now = Date()
        let seconds = Calendar.current.component(.second, from: model.now)
        let untilNextMinute = TimeInterval(60 - seconds) + 0.05
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: untilNextMinute, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.now = Date()
                self.layout() // Breite kann sich aendern (z. B. "Montag" -> "Donnerstag")
                self.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.model.now = Date()
                        self?.layout()
                    }
                }
            }
        }
    }

    /// Nach Aufwachen stimmt die Minute nicht mehr; nach Bildschirmwechsel
    /// die Position nicht.
    private func observeSystemChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
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
