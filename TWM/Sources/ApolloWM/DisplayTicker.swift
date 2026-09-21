import AppKit

/// Calls back once per display refresh (vsync) on the main thread, so the
/// glide steps in time with the screen instead of beating against it.
@MainActor
final class DisplayTicker: NSObject {
    private let tick: @MainActor () -> Void
    private let frameRate: Float
    private var link: CADisplayLink?

    init(frameRate: Float, tick: @escaping @MainActor () -> Void) {
        self.frameRate = frameRate
        self.tick = tick
    }

    func start() {
        guard link == nil, let screen = NSScreen.screens.first else { return }
        let link = screen.displayLink(target: self, selector: #selector(fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: frameRate, preferred: frameRate)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func fire(_ link: CADisplayLink) {
        tick()
    }
}
