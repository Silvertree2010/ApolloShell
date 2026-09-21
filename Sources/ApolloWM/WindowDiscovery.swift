import AppKit
import ApplicationServices

public enum WindowDiscovery {
    /// Whether this process may control other apps' windows. With `prompt`,
    /// macOS shows its permission dialog when access is missing.
    public static func isTrusted(prompt: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    /// The window that has keyboard focus, if any.
    public static func focusedWindowID() -> CGWindowID? {
        let system = AXUIElementCreateSystemWide()
        guard let app = system.value(kAXFocusedApplicationAttribute),
              CFGetTypeID(app) == AXUIElementGetTypeID(),
              let window = (app as! AXUIElement).value(kAXFocusedWindowAttribute),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(window as! AXUIElement, &pid)
        return AXWindow(element: window as! AXUIElement, pid: pid)?.windowID
    }

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
                guard element.string(kAXSubroleAttribute) == kAXStandardWindowSubrole,
                      element.bool(kAXMinimizedAttribute) != true,
                      element.bool("AXFullScreen") != true,
                      let window = AXWindow(element: element, pid: pid),
                      onScreen.contains(window.windowID),
                      // The window server's frame decides, not the app's: windows
                      // parked past the screen edge (ApolloShell edge windows)
                      // still report an on-screen position through the app.
                      let frame = window.serverFrame,
                      area.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
                result.append(window)
            }
        }
        return result.sorted {
            let a = $0.frame ?? .zero, b = $1.frame ?? .zero
            return (a.minX, a.minY) < (b.minX, b.minY)
        }
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
