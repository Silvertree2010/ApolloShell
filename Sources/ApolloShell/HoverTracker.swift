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
        }

        override func mouseEntered(with event: NSEvent) { onChange(true) }
        override func mouseExited(with event: NSEvent) { onChange(false) }

        /// Verschwindet das Fenster, waehrend die Maus drauf ist, kommt kein
        /// mouseExited mehr - dann hier den Hover beenden.
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil { onChange(false) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
