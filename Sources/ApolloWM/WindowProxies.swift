import AppKit
@preconcurrency import ScreenCaptureKit

/// Stand-in images for windows during a glide, the way Hyprland stretches a
/// window's last frame instead of making the app redraw at every size.
///
/// Snapshots are taken ahead of time (after each glide and every few seconds
/// while idle), because capturing costs ~35 ms per window plus ~27 ms for the
/// window list (measured) and a glide must start at once. A snapshot may be a
/// few seconds old; during a 0.3 s glide that does not show.
@MainActor
final class WindowProxies {
    private struct Snapshot {
        let image: CGImage
        let taken: CFTimeInterval
    }

    private var snapshots: [CGWindowID: Snapshot] = [:]
    private var overlays: [CGWindowID: NSWindow] = [:]
    private var refreshing = false

    /// Snapshots older than this are not used.
    var maxAge: CFTimeInterval = 10

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
        let window = overlays[id] ?? makeOverlay()
        window.contentView?.layer?.contents = image
        overlays[id] = window
        move(id, to: frame)
        window.order(.above, relativeTo: Int(id))
        return true
    }

    func move(_ id: CGWindowID, to frame: CGRect) {
        guard let window = overlays[id] else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.setFrame(Self.cocoa(frame), display: false)
        CATransaction.commit()
    }

    func remove(_ id: CGWindowID) {
        overlays.removeValue(forKey: id)?.orderOut(nil)
    }

    func removeAll() {
        for id in Array(overlays.keys) { remove(id) }
    }

    private func makeOverlay() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.transient, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.contentsGravity = .resize
        view.layer?.magnificationFilter = .linear
        view.layer?.minificationFilter = .linear
        window.contentView = view
        return window
    }

    /// Top-left global coordinates to AppKit's bottom-left ones.
    private static func cocoa(_ frame: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
    }

    /// One window-list fetch, then all windows captured in parallel, without
    /// shadows and at full pixel resolution.
    private nonisolated static func capture(_ ids: Set<CGWindowID>) async -> [CGWindowID: CGImage] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
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
