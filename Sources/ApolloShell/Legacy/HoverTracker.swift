import AppKit
import SwiftUI

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

        override func mouseEntered(with event: NSEvent) { report(true) }
        override func mouseExited(with event: NSEvent) { report(false) }

        private func report(_ hovering: Bool) {
            DispatchQueue.main.async { [weak self] in self?.onChange(hovering) }
        }

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
