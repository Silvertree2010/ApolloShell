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
            // Private calls missing (future macOS): the official way, on the
            // main thread like all of AppKit.
            window.raise()
            let pid = window.pid
            DispatchQueue.main.async { NSRunningApplication(processIdentifier: pid)?.activate() }
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

    /// The frontmost app, asked through Accessibility. Never NSWorkspace
    /// off the main thread: reading it there can fire KVO into the host's
    /// SwiftUI models on that thread, which crashed ApolloShell.
    public static func frontmostPID() -> pid_t? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        guard let app = system.value(kAXFocusedApplicationAttribute),
              CFGetTypeID(app) == AXUIElementGetTypeID() else { return nil }
        var pid: pid_t = 0
        return AXUIElementGetPid(app as! AXUIElement, &pid) == .success ? pid : nil
    }

    /// The window that really has focus right now: the frontmost app's
    /// focused window. Safe off the main thread (Accessibility only).
    public static func focusedWindowID() -> CGWindowID? {
        guard let pid = frontmostPID() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        // Chromium apps sometimes name no focused window; their main one counts.
        let window = app.value(kAXFocusedWindowAttribute) ?? app.value(kAXMainWindowAttribute)
        guard let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return (window as! AXUIElement).windowID
    }

    /// The window under `point`, from the window server only. The
    /// Accessibility hit test that used to do this asks whatever app owns
    /// the window, and when that is ApolloShell itself, macOS answers
    /// inside this process on the calling thread; a SwiftUI window asked
    /// off the main thread then traps (it crashed the app twice with the
    /// launcher under the mouse). The window server cannot call back.
    ///
    /// Nil when the topmost window there is not a normal one: a menu, the
    /// menu bar, the Dock, one of our own panels. Call off the main thread.
    public static func window(at point: CGPoint) -> AXWindow? {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]] ?? []
        for info in infos {
            guard (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String],
                  let frame = CGRect(dictionaryRepresentation: bounds as! CFDictionary),
                  frame.contains(point) else { continue }
            // The first one that covers the point decides: anything but a
            // normal window of another app means "no window here".
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != getpid(),
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return WindowDiscovery.window(id: id, pid: pid)
        }
        return nil
    }

    /// Whether the frontmost visible window under `point` belongs to this
    /// process. Safe off the main thread (window server only).
    public static func isOwnWindowOnTop(at point: CGPoint) -> Bool {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]] ?? []
        for info in infos {
            guard (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String],
                  let frame = CGRect(dictionaryRepresentation: bounds as! CFDictionary),
                  frame.contains(point) else { continue }
            return (info[kCGWindowOwnerPID as String] as? pid_t) == getpid()
        }
        return false
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
