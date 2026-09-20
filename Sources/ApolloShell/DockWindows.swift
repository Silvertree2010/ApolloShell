import AppKit
import ApolloShellCore
import ApplicationServices
import CoreGraphics
import SwiftUI

/// Windows of an app through the accessibility API (the app has the
/// permission for the window watch). Without it: an empty list, and the menu
/// then only has the commands.
enum DockWindows {
    struct Window {
        let title: String
        let minimized: Bool
        let element: AXUIElement
        /// For matching against `onScreenWindowIDs` (which windows are
        /// visible on the current space right now). `nil` when the private
        /// function behind it is missing - then the window counts nowhere in
        /// "here vs. elsewhere", and the normal way (activate the app, macOS
        /// switches by itself) takes over.
        let windowID: CGWindowID?
    }

    /// `allSpaces`: windows on other desktops too (for the menu).
    /// Without it: only the current one, sorted front to back (for cycling).
    @MainActor
    static func list(pid: pid_t, allSpaces: Bool = false) -> [Window] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        // When the app hangs, the menu should not hang with it.
        AXUIElementSetMessagingTimeout(app, 0.3)
        var elements = AX.elements(app, kAXWindowsAttribute)
        if allSpaces {
            for element in RemoteWindows.all(pid: pid) where !elements.contains(where: { CFEqual($0, element) }) {
                elements.append(element)
            }
        }
        return elements.compactMap { element in
        // Only real windows, no palettes or sheets.
            guard AX.string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole as String else { return nil }
            return Window(title: AX.string(element, kAXTitleAttribute) ?? "",
                          minimized: (AX.copy(element, kAXMinimizedAttribute) as? NSNumber)?.boolValue ?? false,
                          element: element,
                          windowID: AXWindowID.of(element))
        }
    }

    /// Like a click on the window in the Dock menu: out of the Dock if it is
    /// minimised, make it the main window and raise it, then the app to the
    /// front. In this order macOS switches to the desktop of this window
    /// along the way (and that window is the front one there).
    @MainActor
    static func raise(_ window: Window, of app: NSRunningApplication) {
        if window.minimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        // The order decides (measured 16.09.): first make THIS window the
        // main window and raise it, THEN bring the app forward. The other way
        // round, macOS picks a window itself when bringing the app forward -
        // the last used one - and switches to its desktop for that, although
        // one lies here. Forward through the accessibility API, not through
        // `activate()`: that picks by itself too.
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.3)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        let frontmost = AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        // Without accessibility only the old way is left.
        if frontmost != .success { app.activate() }
    }

    /// The numbers of all windows of the app that lie on a desktop, on other
    /// ones too, plus those put away in the Dock. `kAXWindowsAttribute` only
    /// knows the current desktop (measured: 2 of 21 numbers), so the answer
    /// to "does it have windows elsewhere?" comes out of the window list of
    /// the system. Filtered down to real windows: level 0 and at least
    /// 100 x 100 points, so shadows, helper areas and menus fall away.
    /// wegfallen.
    ///
    /// The list also holds windows an app only keeps in memory after closing
    /// them (measured: 3 of 4 with a file manager). Those lie on no space and
    /// fall away here, otherwise a click on an app without a visible window
    /// would open none.
    ///
    /// `requireSpace: false` for hidden apps: whether their windows lie on a
    /// space meanwhile is not measured. If they fell away, a click would open
    /// a new window on top of unhiding them.
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

    /// Window numbers that are visible right now - not minimised and on the
    /// current space (`CGWindowListCopyWindowInfo` only delivers what the
    /// screen shows right now). With that the Dock click tells "a window
    /// here" from "a window elsewhere" (fixed up 16.09.: otherwise a click
    /// jumped to the space of another window although one lay here - Apple's
    /// Dock stays put in that case).
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

    /// The frontmost window of the app on the screen under the mouse (where
    /// the click happened - so no view has to pass down which screen that
    /// is), when another app's window covers it there (`DockWindowCover`).
    /// `nil`: nothing covered, with a single window or several side by side
    /// as well.
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
            // CGWindowListCopyWindowInfo counts from the top left downwards,
            // NSScreen from the bottom left upwards (Apple's standard) - only
            // needed for matching the screen under the mouse; the overlap
            // itself works out the same in any coordinate system.
            let cocoaCenter = CGPoint(x: x + width / 2, y: primaryHeight - y - height / 2)
            guard screen.frame.contains(cocoaCenter) else { return nil }
            let owner: DockScreenWindow.Owner = pid_t(ownerPID) == pid ? .target : (ownerPID == ownPID ? .ownShell : .other)
            return DockScreenWindow(id: number, owner: owner, layer: layer, x: x, y: y, width: width, height: height)
        }
        return DockWindowCover.nextCovered(in: windows).map(CGWindowID.init)
    }
}

/// The window number (`CGWindowID`) of an accessibility reference - a private
/// function, already used for the way round in `RemoteWindows` (by AltTab or
/// yabai, say). With it, AX windows can be matched against
/// `CGWindowListCopyWindowInfo`, which knows no AX elements.
private enum AXWindowID {
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    /// RTLD_DEFAULT is the pointer -2 on macOS.
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

/// Windows on other desktops. `kAXWindowsAttribute` only delivers those of
/// the current one. AltTab's way: create accessibility elements straight from
/// their number (the private function `_AXUIElementCreateWithRemoteToken` in
/// HIServices, through dlsym) and try the numbers 0 to 999.
/// Measured 14.09.: kitty 3 windows instead of 2 in 46 ms, Vivaldi 16 ms -
/// short enough to do it when the menu opens.
enum RemoteWindows {
    private typealias Create = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    /// RTLD_DEFAULT is the pointer -2 on macOS.
    private static let create: Create? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementCreateWithRemoteToken") else { return nil }
        return unsafeBitCast(symbol, to: Create.self)
    }()
    private static let maxElementID: UInt64 = 1000

    @MainActor
    static func all(pid: pid_t) -> [AXUIElement] {
        guard let create else { return [] }
        // The shape of the token (AltTab): pid, 0, "coco", element number.
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
