import AppKit
@preconcurrency import ScreenCaptureKit

/// Stand-in images for windows during a glide.
///
/// Snapshots are never stretched: the image sits at its own size in the top
/// left corner, like an app's content during a native live resize; space it
/// does not cover takes the window's background color, and a shrinking frame
/// crops it. Meanwhile the real window is resized off screen, captured at its
/// new size and shown once it has finished drawing, so the glide ends on
/// the right content.
///
/// The first snapshot is taken ahead of time (after each glide and every few
/// seconds while idle), because a capture costs ~35 ms plus ~27 ms for the
/// window list (measured) and a glide must start at once.
@MainActor
final class WindowProxies {
    private struct Snapshot {
        let image: CGImage
        let taken: CFTimeInterval
    }

    /// One overlay: the window's background color with rounded corners, the
    /// old snapshot on top, the new one fading in above it.
    private final class Overlay {
        let window: NSWindow
        let old = CALayer()
        let new = CALayer()

        init(cornerRadius: CGFloat) {
            window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.transient, .ignoresCycle]
            let view = NSView()
            view.wantsLayer = true
            let root = view.layer!
            root.cornerRadius = cornerRadius
            root.cornerCurve = .continuous
            root.masksToBounds = true
            for layer in [old, new] {
                // Top left, never scaled (AppKit layers are not flipped, so
                // "top" is the visual top).
                layer.contentsGravity = .topLeft
                layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                root.addSublayer(layer)
            }
            new.opacity = 0
            window.contentView = view
        }
    }

    private var snapshots: [CGWindowID: Snapshot] = [:]
    private var overlays: [CGWindowID: Overlay] = [:]
    /// Windows whose new look has finished drawing and is showing.
    private var ready: Set<CGWindowID> = []
    /// Bumped whenever a window's new look must be prepared again, so an
    /// older preparation still running gives up.
    private var generation: [CGWindowID: Int] = [:]
    private var refreshing = false

    /// Snapshots older than this are not used.
    var maxAge: CFTimeInterval = 10
    /// macOS 26 window corners.
    var cornerRadius: CGFloat = 16

    /// Needs the Screen Recording permission.
    var isAvailable: Bool { CGPreflightScreenCaptureAccess() }

    func has(_ id: CGWindowID) -> Bool { overlays[id] != nil }

    func hasSnapshot(of id: CGWindowID) -> Bool {
        guard let snapshot = snapshots[id] else { return false }
        return CACurrentMediaTime() - snapshot.taken < maxAge
    }

    /// Captures fresh snapshots of `ids` in the background.
    func refresh(_ ids: [CGWindowID]) {
        guard isAvailable, !refreshing, !ids.isEmpty else { return }
        refreshing = true
        Task { [weak self] in
            let images = await Self.capture(Set(ids))
            guard let self else { return }
            let now = CACurrentMediaTime()
            for (id, image) in images { self.snapshots[id] = Snapshot(image: image, taken: now) }
            self.refreshing = false
        }
    }

    func forget(_ id: CGWindowID) {
        snapshots[id] = nil
        remove(id)
    }

    /// Shows the snapshot of `id` at `frame` (top-left coordinates).
    /// Returns false when there is no usable snapshot.
    func show(_ id: CGWindowID, at frame: CGRect) -> Bool {
        guard hasSnapshot(of: id), let image = snapshots[id]?.image else { return false }
        let overlay = overlays[id] ?? Overlay(cornerRadius: cornerRadius)
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.window.contentView?.layer?.backgroundColor = Self.backgroundColor(of: image)
        overlay.old.contents = image
        overlay.old.contentsScale = scale
        overlay.new.contents = nil
        overlay.new.opacity = 0
        CATransaction.commit()
        overlays[id] = overlay
        ready.remove(id)
        move(id, to: frame)
        overlay.window.order(.above, relativeTo: Int(id))
        return true
    }

    /// Whether the window's new look is on screen, so it can be swapped in.
    func isReady(_ id: CGWindowID) -> Bool { ready.contains(id) }

    /// Waits until the real window (resized off screen) has finished drawing
    /// at its new size, then shows that image. Apps like Spotify redraw
    /// piece by piece; a capture taken too early showed half-drawn content
    /// filling in from the bottom right. "Finished" means two captures
    /// 50 ms apart look the same. Gives up after `limit` and uses the last.
    func prepareNewLook(_ id: CGWindowID, limit: TimeInterval = 0.8) {
        guard isAvailable, overlays[id] != nil else { return }
        ready.remove(id)
        let token = (generation[id] ?? 0) + 1
        generation[id] = token
        Task { [weak self] in
            let deadline = CACurrentMediaTime() + limit
            var previous: CGImage?
            var settled: CGImage?
            while CACurrentMediaTime() < deadline {
                guard let image = await Self.capture([id], onScreenOnly: false)[id] else { break }
                if let previous, Self.looksSame(previous, image) {
                    settled = image
                    break
                }
                previous = image
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.generation[id] == token, self.overlays[id] != nil else { return }
            }
            guard let self, self.generation[id] == token, let overlay = self.overlays[id],
                  let image = settled ?? previous else { return }
            self.snapshots[id] = Snapshot(image: image, taken: CACurrentMediaTime())
            // A plain cut: cross-fading reflowed text showed both versions
            // on top of each other (seen in a screen recording).
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            overlay.new.contentsScale = overlay.old.contentsScale
            overlay.new.contents = image
            overlay.new.opacity = 1
            CATransaction.commit()
            self.ready.insert(id)
        }
    }

    /// Same size and, shrunk to 24×16, no channel off by more than a little
    /// on average.
    private static func looksSame(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height,
              let pa = thumbnail(a), let pb = thumbnail(b) else { return false }
        var total = 0
        for i in 0..<pa.count where i % 4 != 3 { total += abs(Int(pa[i]) - Int(pb[i])) }
        return Double(total) / Double(pa.count / 4 * 3) < 2
    }

    private static func thumbnail(_ image: CGImage) -> [UInt8]? {
        let width = 24, height = 16
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    func move(_ id: CGWindowID, to frame: CGRect) {
        guard let overlay = overlays[id] else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.window.setFrame(Self.cocoa(frame), display: false)
        CATransaction.commit()
    }

    func remove(_ id: CGWindowID) {
        ready.remove(id)
        generation[id] = (generation[id] ?? 0) + 1
        overlays.removeValue(forKey: id)?.window.orderOut(nil)
    }

    func removeAll() {
        for id in Array(overlays.keys) { remove(id) }
    }

    /// Top-left global coordinates to AppKit's bottom-left ones.
    private static func cocoa(_ frame: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
    }

    /// The color just inside the bottom-right corner, used to fill space the
    /// snapshot does not cover. Most windows have a plain background there.
    private static func backgroundColor(of image: CGImage) -> CGColor {
        let inset = 24
        let x = max(0, image.width - inset), y = max(0, image.height - inset)
        guard let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return CGColor(gray: 0.1, alpha: 1) }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return CGColor(gray: 0.1, alpha: 1) }
        return CGColor(srgbRed: CGFloat(data[0]) / 255, green: CGFloat(data[1]) / 255,
                       blue: CGFloat(data[2]) / 255, alpha: 1)
    }

    /// One window-list fetch, then all windows captured in parallel, without
    /// shadows and at full pixel resolution.
    private nonisolated static func capture(_ ids: Set<CGWindowID>, onScreenOnly: Bool = true) async -> [CGWindowID: CGImage] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: onScreenOnly)
        else { return [:] }
        let windows = content.windows.filter { ids.contains($0.windowID) }
        return await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
            for window in windows {
                group.addTask {
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    let config = SCStreamConfiguration()
                    let scale = CGFloat(filter.pointPixelScale)
                    config.width = Int(window.frame.width * scale)
                    config.height = Int(window.frame.height * scale)
                    config.ignoreShadowsSingleWindow = true
                    config.showsCursor = false
                    let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    return (window.windowID, image)
                }
            }
            var result: [CGWindowID: CGImage] = [:]
            for await (id, image) in group { if let image { result[id] = image } }
            return result
        }
    }
}
