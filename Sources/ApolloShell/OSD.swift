import AppKit
import SwiftUI

/// Lautstaerke-Anzeige rechts mittig (Caelestia: OSD). Erscheint, wenn sich
/// Lautstaerke oder Stumm aendern (Tasten, Menueleiste, andere Apps),
/// verschwindet nach 2 s - ausser die Maus liegt darauf.
///
/// macOS zeigt bei den Lautstaerketasten zusaetzlich seine eigene Anzeige;
/// die laesst sich nicht abschalten, beide erscheinen dann.
@MainActor
final class OSD {
    /// Caelestia: Config.osd.hideDelay = 2000 ms.
    private static let hideDelay: TimeInterval = 2
    /// Caelestia: Griff zeigt die Zahl noch 500 ms nach der letzten Aenderung.
    private static let movingHold: TimeInterval = 0.5

    private let model = OSDModel()
    private let monitor = VolumeMonitor()
    private let drawer: EdgeDrawer<OSDView>
    private var hideTimer: Timer?
    private var movingTimer: Timer?

    init() {
        let view = OSDView(model: model)
        drawer = EdgeDrawer(
            edge: .right,
            size: NSSize(width: OSDView.width, height: OSDView.height),
            cornerRadius: 28,
            takesKeyboard: false,
            rootView: view
        )
        drawer.closesOnResignKey = false

        model.onDrag = { [weak self] value in
            self?.monitor.setVolume(value)
        }
        model.onHoverChanged = { [weak self] hovered in
            // Maus weg: ab jetzt wieder 2 s bis zum Ausblenden.
            if !hovered { self?.scheduleHide() }
        }
        monitor.onChange = { [weak self] volume, muted in
            self?.show(volume: volume, muted: muted)
        }
        monitor.start()
        model.volume = monitor.volume
        model.muted = monitor.muted
    }

    private func show(volume: Float, muted: Bool) {
        model.volume = volume
        model.muted = muted
        model.moving = true
        movingTimer?.invalidate()
        movingTimer = Timer.scheduledTimer(withTimeInterval: Self.movingHold, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.moving = false }
        }
        drawer.open()
        scheduleHide()
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.hideDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.hovered else { return }
                self.drawer.close()
            }
        }
    }
}
