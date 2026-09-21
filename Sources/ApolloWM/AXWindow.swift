import ApplicationServices
import CoreGraphics
import QuartzCore
import Synchronization

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// One window of another app, driven through the Accessibility API.
/// Frames are in global top-left coordinates (same as CGEvent locations).
///
/// Thread-safety: every Accessibility call is a synchronous IPC round trip to
/// the owning app; the Accessibility API itself is thread-safe. Frame writes
/// run on the app's worker thread (see AppWorker), reads anywhere. The write
/// cache and cost samples are guarded by a lock.
public final class AXWindow: @unchecked Sendable {
    public let element: AXUIElement
    public let pid: pid_t
    public let windowID: CGWindowID
    public let title: String
    /// AXStandardWindow, AXDialog, AXFloatingWindow, ...
    public let subrole: String

    private struct Cache {
        /// Last frame written, used to skip calls that would change nothing.
        var lastWritten: CGRect?
        /// How long the app took for its recent size changes, in seconds.
        var resizeCosts: [Double] = []
    }
    private let cache = Mutex(Cache())

    /// Median of the app's recent size changes. Slow apps (they re-layout a
    /// web page on every size) glide as a snapshot instead.
    public var medianResizeCost: Double? {
        cache.withLock { cache in
            guard cache.resizeCosts.count >= 5 else { return nil }
            return cache.resizeCosts.sorted()[cache.resizeCosts.count / 2]
        }
    }

    init?(element: AXUIElement, pid: pid_t) {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        self.element = element
        self.pid = pid
        self.windowID = id
        self.title = element.string(kAXTitleAttribute) ?? ""
        self.subrole = element.string(kAXSubroleAttribute) ?? ""
        // A hung app must not freeze the animation loop for seconds.
        AXUIElementSetMessagingTimeout(element, 0.25)
    }

    public var frame: CGRect? {
        guard let origin = element.point(kAXPositionAttribute),
              let size = element.size(kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    public var position: CGPoint? { element.point(kAXPositionAttribute) }

    /// Whether the app lets its size be changed at all.
    public var isResizable: Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    /// Frame as the window server sees it. During a title-bar drag the
    /// window server moves the window itself, so this is current even when
    /// the app has not caught up yet.
    public var serverFrame: CGRect? {
        // The API wants raw window numbers stored as pointer values, not CFNumbers.
        var raw = UnsafeRawPointer(bitPattern: UInt(windowID))
        guard let ids = CFArrayCreate(nil, &raw, 1, nil),
              let list = CGWindowListCreateDescriptionFromArray(ids) as? [[String: Any]],
              let bounds = list.first?[kCGWindowBounds as String] else { return nil }
        return CGRect(dictionaryRepresentation: bounds as! CFDictionary)
    }

    /// Writes only the components that changed. Returns false when the window
    /// is gone. When shrinking, size goes first so the move is not clamped by
    /// the screen edge; when growing, position goes first for the same reason.
    @discardableResult
    public func setFrame(_ rect: CGRect) -> Bool {
        // Round each value on its own. `integral` would grow the size by a
        // pixel whenever the origin is fractional, so a window dragged or
        // animated along would change size on every other frame and apps
        // like kitty would reflow and flash.
        let rect = CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(),
                          width: rect.width.rounded(), height: rect.height.rounded())
        let lastWritten = cache.withLock { $0.lastWritten }
        let moved = lastWritten.map { $0.origin != rect.origin } ?? true
        let resized = lastWritten.map { $0.size != rect.size } ?? true
        let shrinking = lastWritten.map { rect.width < $0.width || rect.height < $0.height } ?? false
        // Only what the app accepted is cached; a write that failed (a busy
        // app hit the messaging timeout) is sent again next time.
        var written = lastWritten ?? CGRect(x: CGFloat.nan, y: CGFloat.nan, width: CGFloat.nan, height: CGFloat.nan)
        var cost: Double?
        var ok = true
        func size() {
            guard resized else { return }
            let start = CACurrentMediaTime()
            if element.set(kAXSizeAttribute, size: rect.size) { written.size = rect.size } else { ok = false }
            cost = CACurrentMediaTime() - start
        }
        func position() {
            guard moved else { return }
            if element.set(kAXPositionAttribute, point: rect.origin) { written.origin = rect.origin } else { ok = false }
        }
        if shrinking { size(); position() } else { position(); size() }
        cache.withLock { cache in
            cache.lastWritten = written
            if let cost {
                cache.resizeCosts.append(cost)
                if cache.resizeCosts.count > 30 { cache.resizeCosts.removeFirst(cache.resizeCosts.count - 30) }
            }
        }
        return ok
    }

    /// Asks the app for its size limits before the window is tiled, so it can
    /// glide to the right spot on the first try: request a tiny size, then
    /// `largest` at `origin`, read back what the app accepted, and restore the
    /// frame, all before the window server shows a new frame. Nil when the
    /// app did not react (it applies sizes later); limits are then learned
    /// after the first glide instead.
    public func measureLimits(largest: CGRect) -> (minimum: CGSize, maximum: CGSize)? {
        guard let original = frame else { return nil }
        defer {
            _ = element.set(kAXSizeAttribute, size: original.size)
            _ = element.set(kAXPositionAttribute, point: original.origin)
            invalidateCache()
        }
        guard element.set(kAXSizeAttribute, size: CGSize(width: 1, height: 1)),
              let small = element.size(kAXSizeAttribute) else { return nil }
        _ = element.set(kAXPositionAttribute, point: largest.origin)
        guard element.set(kAXSizeAttribute, size: largest.size),
              let big = element.size(kAXSizeAttribute) else { return nil }
        if small == original.size && big == original.size { return nil }
        // Small shortfalls are apps snapping to character cells, not a limit.
        let maximum = CGSize(width: big.width < largest.width - 20 ? big.width : .infinity,
                             height: big.height < largest.height - 20 ? big.height : .infinity)
        return (small, maximum)
    }

    /// Brings the window to the front of its app's windows.
    public func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    /// Closes the window like its red button does (the app may still ask to
    /// save). Returns false when the window has no close button.
    @discardableResult
    public func close() -> Bool {
        guard let button = element.value(kAXCloseButtonAttribute),
              CFGetTypeID(button) == AXUIElementGetTypeID() else { return false }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    /// Forget the cached frame, e.g. after the user moved the window by hand.
    public func invalidateCache() { cache.withLock { $0.lastWritten = nil } }
}

extension AXUIElement {
    func value(_ attribute: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &ref) == .success else { return nil }
        return ref
    }

    func string(_ attribute: String) -> String? { value(attribute) as? String }
    func bool(_ attribute: String) -> Bool? { (value(attribute) as? NSNumber)?.boolValue }

    func point(_ attribute: String) -> CGPoint? {
        guard let ref = value(attribute), CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(ref as! AXValue, .cgPoint, &p) ? p : nil
    }

    func size(_ attribute: String) -> CGSize? {
        guard let ref = value(attribute), CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(ref as! AXValue, .cgSize, &s) ? s : nil
    }

    func set(_ attribute: String, point: CGPoint) -> Bool {
        var p = point
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(self, attribute as CFString, v) == .success
    }

    func set(_ attribute: String, size: CGSize) -> Bool {
        var s = size
        guard let v = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(self, attribute as CFString, v) == .success
    }

    func set(_ attribute: String, bool: Bool) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, bool as CFBoolean) == .success
    }
}
