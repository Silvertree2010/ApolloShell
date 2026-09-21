import AppKit
import ApplicationServices
import Synchronization

@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

public enum WindowDiscovery {
    /// Whether this process may control other apps' windows. With `prompt`,
    /// macOS shows its permission dialog when access is missing.
    public static func isTrusted(prompt: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    /// The window that has keyboard focus, if any, managed or not.
    public static func focusedWindow() -> AXWindow? {
        let system = AXUIElementCreateSystemWide()
        guard let app = system.value(kAXFocusedApplicationAttribute),
              CFGetTypeID(app) == AXUIElementGetTypeID(),
              let window = (app as! AXUIElement).value(kAXFocusedWindowAttribute),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(window as! AXUIElement, &pid)
        return AXWindow(element: window as! AXUIElement, pid: pid)
    }

    public static func focusedWindowID() -> CGWindowID? { focusedWindow()?.windowID }

    /// Stage Manager shrinks inactive apps' windows to thumbnails at the
    /// screen edge and moves them on every app switch. It fights any tiling
    /// window manager, so hosts should warn when it is on.
    public static var isStageManagerOn: Bool {
        UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
    }

    /// Usable area of the main display (menu bar and Dock excluded),
    /// in global top-left coordinates.
    @MainActor
    public static func mainArea() -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let visible = primary.visibleFrame
        return CGRect(x: visible.minX,
                      y: primary.frame.height - visible.maxY,
                      width: visible.width,
                      height: visible.height)
    }

    /// Normal windows get tiled; dialogs and panels are managed too, but float.
    static let managedSubroles: Set<String> = [
        kAXStandardWindowSubrole, kAXDialogSubrole, kAXSystemDialogSubrole, kAXFloatingWindowSubrole,
    ]

    /// Normal, visible windows on the current Space whose center (as the
    /// window server sees it) lies in `area`, sorted left to right so the
    /// first tiling keeps their rough order.
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
                      // The window server's frame decides, not the app's: Stage
                      // Manager parks windows past the screen edge as thumbnails
                      // while the app still reports an on-screen position.
                      let frame = window.serverFrame,
                      area.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
                result.append(window)
            }
        }
        return result.sorted {
            let a = $0.serverFrame ?? .zero, b = $1.serverFrame ?? .zero
            return (a.minX, a.minY) < (b.minX, b.minY)
        }
    }

    /// A window found on one of the main display's desktops.
    public struct Found: Sendable {
        public let window: AXWindow
        public let space: SpaceID
    }

    /// Normal windows on every desktop of the main display, shown or not,
    /// sorted left to right. Accessibility only lists the shown desktop's
    /// windows, so the others are reached the way yabai does it: an element
    /// made from a remote token (pid, 0, "coco", element number), probing
    /// element numbers until every window the window server knows for the
    /// app is found. Found elements are cached, so later scans only probe
    /// for new windows. Costs 20-80 ms per app the first time (measured);
    /// call it off the main thread.
    public static func allDesktopWindows(in area: CGRect) -> [Found] {
        let own = getpid()
        let desktops = Set(Spaces.ordered())
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
                  // Windows closed but kept alive (WhatsApp, System Settings)
                  // belong to no desktop.
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
                      // On the main display (hidden desktops keep coordinates).
                      frame.midX >= area.minX, frame.midX <= area.maxX,
                      let space = spaceOf[id] else { continue }
                result.append(Found(window: window, space: space))
            }
        }
        return result.sorted {
            let a = $0.window.serverFrame ?? .zero, b = $1.window.serverFrame ?? .zero
            return (a.minX, a.minY) < (b.minX, b.minY)
        }
    }

    /// Accessibility elements are thread-safe to use; the box only tells
    /// the compiler so.
    private struct CachedElement: @unchecked Sendable {
        let element: AXUIElement
        let pid: pid_t
    }

    private static let elementCache = Mutex<[CGWindowID: CachedElement]>([:])

    /// Accessibility elements for `windows` of app `pid`: cached ones, the
    /// shown desktop's from the window list, the rest by probing tokens.
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
            // This app's windows that no longer exist are dropped.
            cache = cache.filter { $0.value.pid != pid || windows.contains($0.key) }
            cache.merge(entries) { _, new in new }
        }
        return result
    }
}

/// Apps with "enhanced user interface" on (set by VoiceOver and some tools)
/// animate every frame change themselves, which makes scripted moves lag.
/// Turn it off while we drive windows and put it back afterwards.
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
