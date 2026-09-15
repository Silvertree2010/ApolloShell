import Foundation
import ApolloShellCore
import Observation

/// Kurzmeldungen unten rechts (Caelestia: Toaster). Jeder Teil der App ruft
/// `toast(...)`; anzeigen tut sie `ToastWindow`, die Regeln (hoechstens 4,
/// 5 s, neueste unten) stehen in `ToastQueue`.
@MainActor
@Observable
final class Toaster {
    private(set) var queue = ToastQueue()
    /// Vollbild: nichts zeigen (Caelestia: `utilities.toasts.fullscreen` =
    /// "off"). Die Meldungen laufen trotzdem ab.
    private(set) var hiddenForFullscreen = false
    /// Wie weit der Stapel ueber seiner Grundlinie schwebt: 0, oder die Hoehe
    /// des offenen Utilities-Panels (Caelestia: `anchors.bottom: utilities.top`).
    var lift: CGFloat = 0

    /// Nach jeder Aenderung an dem, was zu sehen ist - fuers Fenster.
    @ObservationIgnored var onChange: () -> Void = {}
    /// Genau ein Timer, gestellt auf die naechste Ablaufzeit.
    @ObservationIgnored private var expiryTimer: Timer?

    var visible: [ToastEntry] {
        queue.visible(fullscreen: hiddenForFullscreen)
    }

    /// `symbol == nil`: das Symbol der Art (Caelestia: info, warning, ...).
    func toast(title: String, message: String, symbol: String? = nil, kind: ToastKind = .info) {
        queue.push(title: title, message: message, symbol: symbol, kind: kind, now: Date())
        changed()
    }

    func toast(_ content: ToastText.Content) {
        toast(title: content.title, message: content.message, symbol: content.symbol, kind: content.kind)
    }

    /// Klick auf die Meldung (Caelestia: jede Maustaste schliesst).
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
        // .common: laeuft auch, waehrend irgendwo ein Menue offen ist.
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    private func expire() {
        queue.expire(now: Date())
        changed()
    }
}
