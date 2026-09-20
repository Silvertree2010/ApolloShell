import AppKit
import ApolloShellCore
import SwiftUI

/// Volume indicator centered on the right (Caelestia: OSD). Appears when
/// volume or mute changes (keys, menu bar, other apps), disappears after
/// 2 s - unless the mouse is hovering over it.
///
/// macOS also shows its own indicator for the volume keys; that one can't
/// be turned off, so both appear then.
@MainActor
final class OSD {
    /// Caelestia: Config.osd.hideDelay = 2000 ms.
    private static let hideDelay: TimeInterval = 2
    /// Caelestia: the handle still shows the number 500 ms after the last change.
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
            // Mouse gone: 2 s until hiding again from now.
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
