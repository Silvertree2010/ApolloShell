import ApplicationServices
import CoreGraphics
import QuartzCore
import Synchronization

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

public final class AXWindow: @unchecked Sendable {
    public let element: AXUIElement
    public let pid: pid_t
    public let windowID: CGWindowID
    public var title: String { cache.withLock { $0.title } }
    public let subrole: String

    private struct Cache {
        var title = ""
        var lastWritten: CGRect?
        var resizeCosts: [Double] = []
    }
    private let cache = Mutex(Cache())

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
        self.subrole = element.string(kAXSubroleAttribute) ?? ""
        let title = element.string(kAXTitleAttribute) ?? ""
        cache.withLock { $0.title = title }
        AXUIElementSetMessagingTimeout(element, 0.25)
    }

    public var frame: CGRect? {
        guard let origin = element.point(kAXPositionAttribute),
              let size = element.size(kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    public func refreshTitle() -> Bool {
        guard let title = element.string(kAXTitleAttribute) else { return false }
        return cache.withLock { cache in
            guard cache.title != title else { return false }
            cache.title = title
            return true
        }
    }

    public var position: CGPoint? { element.point(kAXPositionAttribute) }

    public var isResizable: Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    public var serverFrame: CGRect? {
        var raw = UnsafeRawPointer(bitPattern: UInt(windowID))
        guard let ids = CFArrayCreate(nil, &raw, 1, nil),
              let list = CGWindowListCreateDescriptionFromArray(ids) as? [[String: Any]],
              let bounds = list.first?[kCGWindowBounds as String] else { return nil }
        return CGRect(dictionaryRepresentation: bounds as! CFDictionary)
    }

    public var serverLayer: Int? {
        var raw = UnsafeRawPointer(bitPattern: UInt(windowID))
        guard let ids = CFArrayCreate(nil, &raw, 1, nil),
              let list = CGWindowListCreateDescriptionFromArray(ids) as? [[String: Any]] else { return nil }
        return list.first?[kCGWindowLayer as String] as? Int
    }

    @discardableResult
    public func setFrame(_ rect: CGRect) -> Bool {
        let rect = CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(),
                          width: rect.width.rounded(), height: rect.height.rounded())
        let lastWritten = cache.withLock { $0.lastWritten }
        let moved = lastWritten.map { $0.origin != rect.origin } ?? true
        let resized = lastWritten.map { $0.size != rect.size } ?? true
        let shrinking = lastWritten.map { rect.width < $0.width || rect.height < $0.height } ?? false
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
        let maximum = CGSize(width: big.width < largest.width - 20 ? big.width : .infinity,
                             height: big.height < largest.height - 20 ? big.height : .infinity)
        return (small, maximum)
    }

    public func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    @discardableResult
    public func close() -> Bool {
        guard let button = element.value(kAXCloseButtonAttribute),
              CFGetTypeID(button) == AXUIElementGetTypeID() else { return false }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    public func invalidateCache() { cache.withLock { $0.lastWritten = nil } }
}

extension AXUIElement {
    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success && id != 0 ? id : nil
    }

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
