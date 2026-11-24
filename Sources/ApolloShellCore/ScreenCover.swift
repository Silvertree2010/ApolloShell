import CoreGraphics
import Foundation

/// Full screen without a full-screen Space: games and players that open a
/// borderless window the size of the screen, or that take the screen at
/// shielding level (exclusive mode). macOS reports neither as full screen,
/// so the windows themselves are looked at (`CGWindowListCopyWindowInfo`,
/// needs no permission). Only the rules live here, so they are testable
/// without a WindowServer.
///
/// All rectangles in CoreGraphics coordinates: origin top left of the main
/// screen, y down, as `kCGWindowBounds` and `CGDisplayBounds` deliver them.
public enum ScreenCover {
    public struct Window: Equatable, Sendable {
        public var pid: Int32
        public var owner: String
        public var layer: Int
        public var alpha: Double
        public var bounds: CGRect

        public init(pid: Int32, owner: String, layer: Int, alpha: Double = 1, bounds: CGRect) {
            self.pid = pid
            self.owner = owner
            self.layer = layer
            self.alpha = alpha
            self.bounds = bounds
        }
    }

    public struct Screen: Equatable, Sendable {
        public var id: UInt32
        public var frame: CGRect

        public init(id: UInt32, frame: CGRect) {
            self.id = id
            self.frame = frame
        }
    }

    /// Apps round, and some games make their window a point larger than the
    /// screen.
    public static let tolerance: CGFloat = 1

    /// Processes of the system whose windows may span a screen without it
    /// being full screen: Mission Control and Launchpad (Dock), Stage
    /// Manager, wallpaper, the menu bar, screenshots, the lock screen.
    public static let systemOwners: Set<String> = [
        "Window Server", "Dock", "WindowManager", "Wallpaper", "Control Center",
        "Notification Center", "SystemUIServer", "loginwindow", "Screenshot",
        "screencaptureui", "universalAccessAuthWarn", "CoreServicesUIAgent",
    ]

    /// `window` reaches over the whole of `screen`.
    public static func covers(_ window: CGRect, _ screen: CGRect) -> Bool {
        guard !screen.isEmpty else { return false }
        return window.insetBy(dx: -tolerance, dy: -tolerance).contains(screen)
    }

    /// Screens on which a window of another app stands in full screen.
    ///
    /// `windows` front to back, as the window list delivers them. A window
    /// counts when it covers the screen completely, is visible, and
    /// - sits at the normal level (0) and no normal window of another app
    ///   lies in front of it on that screen - a game left running behind
    ///   Finder does not hide the bar; or
    /// - sits above the normal level (borderless at menu level, exclusive at
    ///   shielding level) and belongs to the app in front. Transparent
    ///   overlays of tools running in the background (desktop pets, dimmers,
    ///   drawing tools) span the screen too, but are never in front.
    ///
    /// Below the normal level is the desktop. Own windows and those of the
    /// system never count.
    public static func coveredScreens(windows: [Window], screens: [Screen], frontPID: Int32?, ownPID: Int32) -> Set<UInt32> {
        var result: Set<UInt32> = []
        for screen in screens {
            var blocked: Set<Int32> = []
            for window in windows {
                guard window.pid != ownPID, !systemOwners.contains(window.owner),
                      window.alpha > 0, window.layer >= 0
                else { continue }
                if window.layer == 0, !covers(window.bounds, screen.frame) {
                    let overlap = window.bounds.intersection(screen.frame)
                    if !overlap.isNull, overlap.width > 0, overlap.height > 0 { blocked.insert(window.pid) }
                    continue
                }
                guard covers(window.bounds, screen.frame) else { continue }
                if window.layer == 0 {
                    if blocked.subtracting([window.pid]).isEmpty { result.insert(screen.id) }
                    break
                }
                if window.pid == frontPID {
                    result.insert(screen.id)
                    break
                }
            }
        }
        return result
    }

    /// Entries of `CGWindowListCopyWindowInfo` that can be read; the order
    /// stays.
    public static func windows(_ list: [[String: Any]]) -> [Window] {
        list.compactMap { entry in
            guard let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let raw = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary)
            else { return nil }
            return Window(
                pid: pid,
                owner: entry[kCGWindowOwnerName as String] as? String ?? "",
                layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                alpha: (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                bounds: bounds
            )
        }
    }
}
