import AppKit
import ApplicationServices

// Window-server calls yabai uses to focus one exact window (MIT licensed
// technique, see github.com/koekeishiya/yabai window_manager.c). They need
// no SIP changes. Looked up at run time, so nothing links against the
// private SkyLight framework.
private typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> CGError
private typealias PostEventRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
private typealias ProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

private struct SkyLight: @unchecked Sendable {
    let setFrontProcess: SetFrontProcess?
    let postEventRecord: PostEventRecord?
    let processForPID: ProcessForPID?

    static let shared: SkyLight = {
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        let services = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
        func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        return SkyLight(setFrontProcess: symbol(skyLight, "_SLPSSetFrontProcessWithOptions", as: SetFrontProcess.self),
                        postEventRecord: symbol(skyLight, "SLPSPostEventRecordTo", as: PostEventRecord.self),
                        processForPID: symbol(services, "GetProcessForPID", as: ProcessForPID.self))
    }()
}

/// Focusing and asking about focus, the robust way.
///
/// `NSRunningApplication.activate()` goes through macOS 14's cooperative
/// activation: a background app asking to activate another one is sometimes
/// ignored, which made focus follows mouse feel unreliable. Like yabai and
/// AutoRaise, this tells the window server directly which process is in
/// front and which of its windows is key, so exactly that window gets focus.
public enum WindowFocus {
    private static let userGenerated: UInt32 = 0x200

    /// Brings `window` to the front and makes it the key window.
    /// Call off the main thread (the raise is a round trip into the app).
    public static func focus(_ window: AXWindow) {
        let sky = SkyLight.shared
        var psn = ProcessSerialNumber()
        guard let processForPID = sky.processForPID, let setFront = sky.setFrontProcess,
              processForPID(window.pid, &psn) == noErr else {
            // Private calls missing (future macOS): the official way.
            window.raise()
            NSRunningApplication(processIdentifier: window.pid)?.activate()
            return
        }
        _ = setFront(&psn, window.windowID, userGenerated)
        makeKey(window.windowID, of: &psn)
        window.raise()
    }

    /// The event record the window server uses to make a window key: sent
    /// once as "mouse down" (1) and once as "mouse up" (2) on the window.
    private static func makeKey(_ windowID: CGWindowID, of psn: inout ProcessSerialNumber) {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID) { id in
            for (offset, byte) in id.enumerated() { bytes[0x3c + offset] = byte }
        }
        for offset in 0x20..<0x30 { bytes[offset] = 0xff }
        guard let post = SkyLight.shared.postEventRecord else { return }
        for phase: UInt8 in [0x01, 0x02] {
            bytes[0x08] = phase
            _ = post(&psn, &bytes)
        }
    }

    /// The window that really has focus right now: the frontmost app's
    /// focused window. Call off the main thread.
    public static func focusedWindowID() -> CGWindowID? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let window = app.value(kAXFocusedWindowAttribute),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return (window as! AXUIElement).windowID
    }

    /// The window under `point`, as the system sees it: the element there,
    /// walked up to its window. Menus, the menu bar and Dock items count as
    /// no window. Call off the main thread.
    public static func window(at point: CGPoint) -> AXWindow? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }
        let skipped: Set<String> = [kAXMenuRole, kAXMenuItemRole, kAXMenuBarRole, kAXMenuBarItemRole, "AXDockItem"]
        for _ in 0..<20 {
            let role = element.string(kAXRoleAttribute) ?? ""
            if skipped.contains(role) { return nil }
            if role == kAXWindowRole || role == kAXSheetRole || role == kAXDrawerRole { break }
            if let window = element.value(kAXWindowAttribute), CFGetTypeID(window) == AXUIElementGetTypeID() {
                element = window as! AXUIElement
                break
            }
            guard let parent = element.value(kAXParentAttribute),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            element = parent as! AXUIElement
        }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return AXWindow(element: element, pid: pid)
    }

    /// Whether Mission Control, the app switcher or a Dock menu is showing
    /// (the Dock then owns a window above the normal layer).
    public static func dockIsBusy() -> Bool {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return infos.contains {
            ($0[kCGWindowOwnerName as String] as? String) == "Dock"
                && ($0[kCGWindowLayer as String] as? Int ?? 0) > 20
        }
    }
}
