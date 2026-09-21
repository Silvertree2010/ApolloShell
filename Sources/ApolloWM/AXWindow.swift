import ApplicationServices
import CoreGraphics

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// One window of another app, driven through the Accessibility API.
/// Frames are in global top-left coordinates (same as CGEvent locations).
///
/// Thread-safety: every Accessibility call is a synchronous IPC round trip to
/// the owning app. Calls for different windows may run concurrently; calls for
/// the same window must not overlap (the engine guarantees that).
public final class AXWindow: @unchecked Sendable {
    public let element: AXUIElement
    public let pid: pid_t
    public let windowID: CGWindowID
    public let title: String

    /// Last frame we wrote, used to skip calls that would change nothing.
    private var lastWritten: CGRect?

    init?(element: AXUIElement, pid: pid_t) {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        self.element = element
        self.pid = pid
        self.windowID = id
        self.title = element.string(kAXTitleAttribute) ?? ""
        // A hung app must not freeze the animation loop for seconds.
        AXUIElementSetMessagingTimeout(element, 0.25)
    }

    public var frame: CGRect? {
        guard let origin = element.point(kAXPositionAttribute),
              let size = element.size(kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    public var position: CGPoint? { element.point(kAXPositionAttribute) }

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
        let rect = rect.integral
        let moved = lastWritten.map { $0.origin != rect.origin } ?? true
        let resized = lastWritten.map { $0.size != rect.size } ?? true
        let shrinking = lastWritten.map { rect.width < $0.width || rect.height < $0.height } ?? false
        var ok = true
        if shrinking {
            if resized { ok = element.set(kAXSizeAttribute, size: rect.size) && ok }
            if moved { ok = element.set(kAXPositionAttribute, point: rect.origin) && ok }
        } else {
            if moved { ok = element.set(kAXPositionAttribute, point: rect.origin) && ok }
            if resized { ok = element.set(kAXSizeAttribute, size: rect.size) && ok }
        }
        lastWritten = rect
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
            lastWritten = nil
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

    /// Forget the cached frame, e.g. after the user moved the window by hand.
    public func invalidateCache() { lastWritten = nil }
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
