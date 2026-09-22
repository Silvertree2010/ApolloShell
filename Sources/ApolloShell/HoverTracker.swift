import AppKit
import SwiftUI

/// Reliably reports whether the mouse is over a view.
///
/// SwiftUI's `onHover` relies on tracking areas which, for windows of a never-
/// active app (bar, launcher menus), don't always report a "mouse left"
/// event - the hover effect then stayed stuck. This tracking area applies
/// always (`.activeAlways`), regardless of which window is currently active.
///
/// Clicks pass through it to the button underneath.
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

        required init?(coder: NSCoder) { fatalError("not used") }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) { report(true) }
        override func mouseExited(with event: NSEvent) { report(false) }

        /// Delivered one run-loop turn later: a hover change can make SwiftUI
        /// tear down other tracking views while AppKit is still routing the
        /// same enter/exit batch to them, which crashed on a freed view.
        private func report(_ hovering: Bool) {
            DispatchQueue.main.async { [weak self] in self?.onChange(hovering) }
        }

        /// If the window disappears while the mouse is on it, no
        /// mouseExited arrives anymore - so end the hover here instead.
        /// The tracking area goes too, so AppKit can't route to a view
        /// that is about to be freed.
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
