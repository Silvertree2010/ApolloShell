import AppKit
import ApplicationServices
import Synchronization

@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

public enum WindowDiscovery {
    public static func isTrusted(prompt: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    public static func focusedWindow() -> AXWindow? {
        guard let app = focusedApplication() else { return nil }
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            guard let window = app.value(attribute), CFGetTypeID(window) == AXUIElementGetTypeID() else { continue }
            var pid: pid_t = 0
            AXUIElementGetPid(window as! AXUIElement, &pid)
            if let found = AXWindow(element: window as! AXUIElement, pid: pid) { return found }
        }
        return nil
    }

    public static func focusedWindowID() -> CGWindowID? {
        if let id = focusedWindow()?.windowID { return id }
        guard let app = focusedApplication() else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(app, &pid)
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]] ?? []
        return infos.first {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }?[kCGWindowNumber as String] as? CGWindowID
    }

    private static func focusedApplication() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        guard let app = system.value(kAXFocusedApplicationAttribute),
              CFGetTypeID(app) == AXUIElementGetTypeID() else { return nil }
        return (app as! AXUIElement)
    }

    public static var isStageManagerOn: Bool {
        UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
    }

    @MainActor
    public static func mainArea() -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let visible = primary.visibleFrame
        return CGRect(x: visible.minX,
                      y: primary.frame.height - visible.maxY,
                      width: visible.width,
                      height: visible.height)
    }

    static let managedSubroles: Set<String> = [
        kAXStandardWindowSubrole, kAXDialogSubrole, kAXSystemDialogSubrole, kAXFloatingWindowSubrole,
    ]

    public static func tileableWindows(in area: CGRect) -> [AXWindow] {
        let own = getpid()
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]] ?? []
        var onScreen = Set<CGWindowID>()
        var pids: [pid_t] = []
        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            onScreen.insert(id)
            if !pids.contains(pid) { pids.append(pid) }
        }

        var result: [AXWindow] = []
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.5)
            guard let elements = app.value(kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for element in elements {
                guard managedSubroles.contains(element.string(kAXSubroleAttribute) ?? ""),
                      element.bool(kAXMinimizedAttribute) != true,
                      element.bool("AXFullScreen") != true,
                      let window = AXWindow(element: element, pid: pid),
                      onScreen.contains(window.windowID),
                      let frame = window.serverFrame,
                      area.intersects(frame) else { continue }
                result.append(window)
            }
        }
        return result.sorted {
            let a = $0.serverFrame ?? .zero, b = $1.serverFrame ?? .zero
            return (a.minX, a.minY) < (b.minX, b.minY)
        }
    }

    public struct Found: Sendable {
        public let window: AXWindow
        public let space: SpaceID
    }

    public static func allDesktopWindows(on screens: [CGRect]) -> [Found] {
        let own = getpid()
        let desktops = Set(Spaces.displays().flatMap(\.desktops)).union(Spaces.ordered())
        let infos = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]] ?? []
        var wanted: [pid_t: Set<CGWindowID>] = [:]
        var spaceOf: [CGWindowID: SpaceID] = [:]
        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String],
                  let frame = CGRect(dictionaryRepresentation: bounds as! CFDictionary),
                  frame.width > 50, frame.height > 50,
                  let space = Spaces.of(id), desktops.contains(space) else { continue }
            wanted[pid, default: []].insert(id)
            spaceOf[id] = space
        }

        var result: [Found] = []
        for (pid, ids) in wanted {
            for (id, element) in elements(for: pid, windows: ids) {
                guard managedSubroles.contains(element.string(kAXSubroleAttribute) ?? ""),
                      element.bool(kAXMinimizedAttribute) != true,
                      element.bool("AXFullScreen") != true,
                      let window = AXWindow(element: element, pid: pid), window.windowID == id,
                      let frame = window.serverFrame,
                      screens.isEmpty || screens.contains(where: { $0.intersects(frame) }),
                      let space = spaceOf[id] else { continue }
                result.append(Found(window: window, space: space))
            }
        }
        return result.sorted {
            let a = $0.window.serverFrame ?? .zero, b = $1.window.serverFrame ?? .zero
            return (a.minX, a.minY) < (b.minX, b.minY)
        }
    }

    public static func window(id: CGWindowID, pid: pid_t) -> AXWindow? {
        if let cached = elementCache.withLock({ $0[id] }), cached.pid == pid {
            return AXWindow(element: cached.element, pid: pid)
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        for element in app.value(kAXWindowsAttribute) as? [AXUIElement] ?? [] where element.windowID == id {
            return AXWindow(element: element, pid: pid)
        }
        return nil
    }

    private struct CachedElement: @unchecked Sendable {
        let element: AXUIElement
        let pid: pid_t
    }

    private static let elementCache = Mutex<[CGWindowID: CachedElement]>([:])

    private static func elements(for pid: pid_t, windows: Set<CGWindowID>) -> [CGWindowID: AXUIElement] {
        var result: [CGWindowID: AXUIElement] = [:]
        let cached = elementCache.withLock { cache in cache.filter { windows.contains($0.key) } }
        for (id, entry) in cached { result[id] = entry.element }
        var missing = windows.subtracting(result.keys)
        if !missing.isEmpty {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.5)
            for element in app.value(kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                if let id = element.windowID, missing.remove(id) != nil { result[id] = element }
            }
        }
        if !missing.isEmpty {
            var token = Data(count: 20)
            token.withUnsafeMutableBytes { raw in
                raw.storeBytes(of: pid, toByteOffset: 0, as: Int32.self)
                raw.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
                raw.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self)
            }
            for number in UInt64(0)..<2000 where !missing.isEmpty {
                token.withUnsafeMutableBytes { $0.storeBytes(of: number, toByteOffset: 12, as: UInt64.self) }
                guard let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue(),
                      element.string(kAXRoleAttribute) == kAXWindowRole,
                      let id = element.windowID, missing.remove(id) != nil else { continue }
                AXUIElementSetMessagingTimeout(element, 0.25)
                result[id] = element
            }
        }
        let entries = result.mapValues { CachedElement(element: $0, pid: pid) }
        elementCache.withLock { cache in
            cache = cache.filter { $0.value.pid != pid || windows.contains($0.key) }
            cache.merge(entries) { _, new in new }
        }
        return result
    }
}

public final class EnhancedUIGuard {
    private var previous: [pid_t: Bool] = [:]

    public init() {}

    public func disable(for pids: some Sequence<pid_t>) {
        for pid in pids where previous[pid] == nil {
            let app = AXUIElementCreateApplication(pid)
            let was = app.bool("AXEnhancedUserInterface") ?? false
            previous[pid] = was
            if was { _ = app.set("AXEnhancedUserInterface", bool: false) }
        }
    }

    public func restore() {
        for (pid, was) in previous where was {
            _ = AXUIElementCreateApplication(pid).set("AXEnhancedUserInterface", bool: true)
        }
        previous.removeAll()
    }
}
