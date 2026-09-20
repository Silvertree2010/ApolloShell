import Foundation
import ApolloShellCore
import Observation

/// Toasts at the bottom right (Caelestia: Toaster). Every part of the app
/// calls `toast(...)`; `ToastWindow` does the showing, the rules (at most 4,
/// 5 s, newest at the bottom) live in `ToastQueue`.
@MainActor
@Observable
final class Toaster {
    private(set) var queue = ToastQueue()
    /// Fullscreen: show nothing (Caelestia: `utilities.toasts.fullscreen` =
    /// "off"). The toasts still run their course regardless.
    private(set) var hiddenForFullscreen = false
    /// How far the stack floats above its baseline: 0, or the height
    /// of the open utilities panel (Caelestia: `anchors.bottom: utilities.top`).
    var lift: CGFloat = 0

    /// After every change to what is visible - for the window.
    @ObservationIgnored var onChange: () -> Void = {}
    /// Exactly one timer, set to the next expiry time.
    @ObservationIgnored private var expiryTimer: Timer?

    var visible: [ToastEntry] {
        queue.visible(fullscreen: hiddenForFullscreen)
    }

    /// `symbol == nil`: the symbol of the kind (Caelestia: info, warning, ...).
    func toast(title: String, message: String, symbol: String? = nil, kind: ToastKind = .info) {
        queue.push(title: title, message: message, symbol: symbol, kind: kind, now: Date())
        changed()
    }

    func toast(_ content: ToastText.Content) {
        toast(title: content.title, message: content.message, symbol: content.symbol, kind: content.kind)
    }

    /// Click on the toast (Caelestia: any mouse button closes it).
    func dismiss(_ id: Int) {
        if queue.dismiss(id: id) { changed() }
    }

    func setHiddenForFullscreen(_ hidden: Bool) {
        guard hidden != hiddenForFullscreen else { return }
        hiddenForFullscreen = hidden
        changed()
    }

    private func changed() {
        scheduleExpiry()
        onChange()
    }

    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        guard let deadline = queue.nextDeadline else { return }
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.expire() }
        }
        // .common: keeps running even while some menu is open.
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    private func expire() {
        queue.expire(now: Date())
        changed()
    }
}
