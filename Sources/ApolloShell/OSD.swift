import AppKit
import ApolloShellCore
import SwiftUI

/// Lautstaerke-Anzeige rechts mittig (Caelestia: OSD). Erscheint, wenn sich
/// Lautstaerke oder Stumm aendern (Tasten, Menueleiste, andere Apps),
/// verschwindet nach 2 s - ausser die Maus liegt darauf.
@MainActor
final class OSD {
    /// Caelestia: Config.osd.hideDelay = 2000 ms.
    private static let hideDelay: TimeInterval = 2
    /// Caelestia: Griff zeigt die Zahl noch 500 ms nach der letzten Aenderung.
    private static let movingHold: TimeInterval = 0.5

    private let model = OSDModel()
    private let monitor = VolumeMonitor()
    private let drawer: EdgeDrawer<OSDView>
    private let keys = MediaKeyTap()
    private var hideTimer: Timer?
    private var movingTimer: Timer?
    private var observation: Task<Void, Never>?
    private(set) var enabled = true

    init(settings: ShellSettingsStore) {
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
            guard let self else { return }
            if self.model.bright {
                self.model.brightness = value
                OSDBrightness.set(value)
            } else {
                self.monitor.setVolume(value)
            }
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
        keys.onKey = { [weak self] key, fine, down in self?.press(key, fine: fine, down: down) ?? false }
        observation = Task { [weak self, settings] in
            for await f in Observations({ settings.settings.features }) {
                self?.apply(f)
            }
        }
    }

    private func apply(_ f: ShellSettings.Features) {
        enabled = f.osd
        if !f.osd { drawer.close() }
        let replace = f.osd && f.replaceSystemOSD
        keys.setEnabled(replace)
        SystemInputIndicator.setHidden(replace)
    }

    private func press(_ key: SystemKey, fine: Bool, down: Bool) -> Bool {
        switch key {
        case .volumeUp, .volumeDown, .mute:
            guard monitor.volumeSettable else { return false }
        case .brightnessUp, .brightnessDown:
            guard OSDBrightness.get() != nil else { return false }
        }
        guard down else { return true }
        let d = SystemKey.step(fine: fine)
        switch key {
        case .volumeUp, .volumeDown:
            let m = monitor.muted
            let v = SystemKey.stepped(monitor.volume, by: key == .volumeUp ? d : -d)
            monitor.setVolume(v)
            show(volume: v, muted: m && v == 0)
        case .mute:
            let m = !monitor.muted
            monitor.setMuted(m)
            show(volume: monitor.volume, muted: m)
        case .brightnessUp, .brightnessDown:
            let cur = OSDBrightness.get() ?? model.brightness
            let v = SystemKey.stepped(cur, by: key == .brightnessUp ? d : -d)
            OSDBrightness.set(v)
            showBrightness(v)
        }
        return true
    }

    func showBrightness(_ v: Float) {
        guard enabled else { return }
        model.bright = true
        model.brightness = v
        drawer.open()
        scheduleHide()
    }

    private func show(volume: Float, muted: Bool) {
        guard enabled else { return }
        model.bright = false
        model.volume = volume
        model.muted = muted
        model.moving = true
        movingTimer?.invalidate()
        movingTimer = .once(after: Self.movingHold, owner: self) { $0.model.moving = false }
        drawer.open()
        scheduleHide()
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = .once(after: Self.hideDelay, owner: self) { osd in
            guard !osd.model.hovered else { return }
            osd.drawer.close()
        }
    }
}
