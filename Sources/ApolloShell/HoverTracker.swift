import AppKit
import SwiftUI

/// Meldet zuverlaessig, ob die Maus ueber einer Ansicht ist.
///
/// SwiftUIs `onHover` haengt an Tracking-Areas, die bei Fenstern einer nie
/// aktiven App (Leiste, Menues des Launchers) nicht immer ein "Maus weg"
/// melden - der Hover-Effekt blieb dann stehen. Diese Tracking-Area gilt
/// immer (`.activeAlways`), egal welches Fenster gerade aktiv ist.
///
/// Klicks gehen durch sie hindurch an den Knopf darunter.
struct HoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        TrackingView(onChange: onChange)
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: (Bool) -> Void
        private var inside = false

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("nicht benutzt") }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
            guard inside, let w = window else { return }
            if !visibleRect.contains(convert(w.mouseLocationOutsideOfEventStream, from: nil)) { report(false) }
        }

        override func mouseEntered(with event: NSEvent) { report(true) }
        override func mouseExited(with event: NSEvent) { report(false) }

        /// Einen Runloop-Durchgang spaeter melden: ein Hover-Wechsel kann SwiftUI
        /// andere Tracking-Ansichten abbauen lassen, waehrend AppKit dieselben
        /// Enter/Exit-Ereignisse noch verteilt - das stuerzte auf einer
        /// freigegebenen Ansicht ab.
        private func report(_ hovering: Bool) {
            inside = hovering
            DispatchQueue.main.async { [weak self] in self?.onChange(hovering) }
        }

        /// Verschwindet das Fenster, waehrend die Maus drauf ist, kommt kein
        /// mouseExited mehr - dann hier den Hover beenden.
        /// Die Tracking-Area geht mit, damit AppKit nicht an eine Ansicht
        /// liefert, die gleich freigegeben wird.
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                for area in trackingAreas { removeTrackingArea(area) }
                onChange(false)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
