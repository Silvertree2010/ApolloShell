import AppKit
import ApolloShellCore
import ApplicationServices
import CoreGraphics
import SwiftUI

enum DockWindows {
    struct Window {
        let title: String
        let minimized: Bool
        let element: AXUIElement
        let windowID: CGWindowID?
    }

    @MainActor
    static func list(pid: pid_t, allSpaces: Bool = false) -> [Window] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var elements = AX.elements(app, kAXWindowsAttribute)
        if allSpaces {
            for element in RemoteWindows.all(pid: pid) where !elements.contains(where: { CFEqual($0, element) }) {
                elements.append(element)
            }
        }
        return elements.compactMap { element in
            guard AX.string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole as String else { return nil }
            return Window(title: AX.string(element, kAXTitleAttribute) ?? "",
                          minimized: (AX.copy(element, kAXMinimizedAttribute) as? NSNumber)?.boolValue ?? false,
                          element: element,
                          windowID: AXWindowID.of(element))
        }
    }

    @MainActor
    static func raise(_ window: Window, of app: NSRunningApplication) {
        if window.minimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.3)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        let frontmost = AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if frontmost != .success { app.activate() }
    }

    @MainActor
    static func allWindowIDs(pid: pid_t, requireSpace: Bool = true) -> Set<CGWindowID> {
        guard let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids: Set<CGWindowID> = []
        for entry in info {
            guard let owner = entry[kCGWindowOwnerPID as String] as? Int, pid_t(owner) == pid,
                  (entry[kCGWindowLayer as String] as? Int) == 0,
                  let number = entry[kCGWindowNumber as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double,
                  width >= 100, height >= 100
            else { continue }
            ids.insert(CGWindowID(number))
        }
        guard requireSpace, let reader = spaceReader else { return ids }
        return ids.filter { reader.isOnAnySpace($0) != false }
    }

    @MainActor private static let spaceReader = SpaceReader()

    @MainActor
    static func onScreenWindowIDs(pid: pid_t) -> Set<CGWindowID> {
        guard let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids: Set<CGWindowID> = []
        for entry in info {
            guard let owner = entry[kCGWindowOwnerPID as String] as? Int, pid_t(owner) == pid,
                  let number = entry[kCGWindowNumber as String] as? Int
            else { continue }
            ids.insert(CGWindowID(number))
        }
        return ids
    }

    @MainActor
    static func coveredWindowID(pid: pid_t) -> CGWindowID? {
        guard let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        else { return nil }
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        let windows: [DockScreenWindow] = info.compactMap { entry in
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? Int,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let number = entry[kCGWindowNumber as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
                  let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double
            else { return nil }
            let cocoaCenter = CGPoint(x: x + width / 2, y: primaryHeight - y - height / 2)
            guard screen.frame.contains(cocoaCenter) else { return nil }
            let owner: DockScreenWindow.Owner = pid_t(ownerPID) == pid ? .target : (ownerPID == ownPID ? .ownShell : .other)
            return DockScreenWindow(id: number, owner: owner, layer: layer, x: x, y: y, width: width, height: height)
        }
        return DockWindowCover.nextCovered(in: windows).map(CGWindowID.init)
    }
}

private enum AXWindowID {
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindow: GetWindow? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: GetWindow.self)
    }()

    static func of(_ element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var id: CGWindowID = 0
        return getWindow(element, &id) == .success ? id : nil
    }
}

enum RemoteWindows {
    private typealias Create = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private static let create: Create? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementCreateWithRemoteToken") else { return nil }
        return unsafeBitCast(symbol, to: Create.self)
    }()
    private static let maxElementID: UInt64 = 1000

    @MainActor
    static func all(pid: pid_t) -> [AXUIElement] {
        guard let create else { return [] }
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
        var windows: [AXUIElement] = []
        for elementID in 0..<maxElementID {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let element = create(token as CFData)?.takeRetainedValue(),
                  AX.string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole as String
            else { continue }
            windows.append(element)
        }
        return windows
    }
}
