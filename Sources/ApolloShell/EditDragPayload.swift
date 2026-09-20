import SwiftUI
import UniformTypeIdentifiers

/// Every drag of the edit mode carries a text payload with a prefix of its
/// own: `apolloshell.widget:`, `.toggle:`, `.card:`, `.bar:`,
/// `.bar.entry:`. Each of the three surfaces has drop targets that read
/// these - and each used to accept every text it was handed, whether the
/// payload belonged to it or not. A quick toggle dropped on the dashboard
/// then vanished without landing and without snapping back.
///
/// `NSItemProvider` only hands the text over asynchronously, so a target
/// cannot decide on the spot. It reads the payload once on entry and keeps
/// what it found here; there is only ever one drag on the machine at a
/// time, so one place is enough for all of them. While nothing has been
/// read yet, everything is still allowed - as before.
@MainActor
enum EditDragPayload {
    enum Home: Equatable {
        case dashboard, controlCentre, bar
    }

    /// The surface a payload belongs to, as far as its prefix says. An
    /// unprefixed payload (a tile or a card being moved inside the control
    /// centre carries its bare id) stays `nil`: nobody refuses it, which is
    /// what those moves rely on.
    static func home(of text: String) -> Home? {
        if text.hasPrefix(BentoWidgetDragPayload.prefix) { return .dashboard }
        if text.hasPrefix(UtilitiesToggleDragPayload.prefix) || text.hasPrefix(UtilitiesCardDragPayload.prefix) {
            return .controlCentre
        }
        // The entry prefix starts with the kind prefix, so it is asked first.
        if text.hasPrefix(BarEntryDragPayload.prefix) || text.hasPrefix(BarModuleDragPayload.prefix) { return .bar }
        return nil
    }

    private(set) static var current: Home?

    /// Reads the payload of this drag once and remembers where it is at
    /// home. Called from `dropEntered`.
    ///
    /// Forgets the old answer on the spot, before it reads: what was left
    /// standing from the last drag belongs to no target of this one, and
    /// the few milliseconds until the text arrives would otherwise be
    /// spent turning a drag down that is perfectly fine.
    static func remember(_ info: DropInfo, types: [UTType]) {
        current = nil
        guard let provider = info.itemProviders(for: types).first else { return }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let text = value as? String else { return }
            DispatchQueue.main.async { current = home(of: text) }
        }
    }

    static func forget() { current = nil }

    #if DEBUG
    /// Self-test: the two halves of `remember` without a drag session -
    /// what a payload is sorted as, and that reading a new one forgets the
    /// old answer first.
    static func debugRemember(_ text: String) { current = home(of: text) }
    static func debugBeginReading() { current = nil }
    #endif

    /// True while the payload is known and belongs somewhere else. The
    /// target then proposes `.forbidden` and turns the drop down, so the
    /// tile goes back where it came from.
    static func refuses(_ mine: Home) -> Bool {
        guard let current else { return false }
        return current != mine
    }
}
