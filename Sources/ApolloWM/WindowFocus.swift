import AppKit
import ApplicationServices

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

public enum WindowFocus {
    private static let userGenerated: UInt32 = 0x200

    public static func focus(_ window: AXWindow) {
        let sky = SkyLight.shared
        var psn = ProcessSerialNumber()
        guard let processForPID = sky.processForPID, let setFront = sky.setFrontProcess,
              processForPID(window.pid, &psn) == noErr else {
            window.raise()
            let pid = window.pid
            DispatchQueue.main.async { NSRunningApplication(processIdentifier: pid)?.activate() }
            return
        }
        _ = setFront(&psn, window.windowID, userGenerated)
        makeKey(window.windowID, of: &psn)
        window.raise()
    }

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

    public static func frontmostPID() -> pid_t? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        guard let app = system.value(kAXFocusedApplicationAttribute),
              CFGetTypeID(app) == AXUIElementGetTypeID() else { return nil }
        var pid: pid_t = 0
        return AXUIElementGetPid(app as! AXUIElement, &pid) == .success ? pid : nil
    }

    public static func focusedWindowID() -> CGWindowID? {
        guard let pid = frontmostPID() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        let window = app.value(kAXFocusedWindowAttribute) ?? app.value(kAXMainWindowAttribute)
        guard let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return (window as! AXUIElement).windowID
    }

    public static func window(at point: CGPoint) -> AXWindow? {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]] ?? []
        for info in infos {
            guard (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String],
                  let frame = CGRect(dictionaryRepresentation: bounds as! CFDictionary),
                  frame.contains(point) else { continue }
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != getpid(),
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return WindowDiscovery.window(id: id, pid: pid)
        }
        return nil
    }

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

    public static func dockIsBusy() -> Bool {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return infos.contains {
            ($0[kCGWindowOwnerName as String] as? String) == "Dock"
                && ($0[kCGWindowLayer as String] as? Int ?? 0) > 20
        }
    }
}
