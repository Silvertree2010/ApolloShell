import AppKit
import Foundation

/// A macOS Space (desktop), as the window server numbers it.
public typealias SpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSManagedDisplayGetCurrentSpace")
private func CGSManagedDisplayGetCurrentSpace(_ cid: Int32, _ display: CFString) -> SpaceID

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> Unmanaged<CFArray>?

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> Unmanaged<CFArray>?

/// Read-only access to macOS Spaces. Uses private window-server calls (the
/// same ones yabai and others use for reading); nothing here changes Spaces,
/// so System Integrity Protection can stay on.
public enum Spaces {
    private static let allSpacesMask: Int32 = 0x7

    /// The Space currently shown on the main display.
    public static func current() -> SpaceID? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue(),
              let name = CFUUIDCreateString(nil, uuid) else { return nil }
        let space = CGSManagedDisplayGetCurrentSpace(CGSMainConnectionID(), name)
        return space == 0 ? nil : space
    }

    /// The main display's desktops in the order Mission Control shows them
    /// (full-screen apps left out).
    public static func ordered() -> [SpaceID] {
        guard let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue()
                as? [[String: Any]] else { return [] }
        let main = current()
        let display = displays.first { ($0["Spaces"] as? [[String: Any]])?.contains {
            ($0["id64"] as? NSNumber)?.uint64Value == main } ?? false } ?? displays.first
        let spaces = display?["Spaces"] as? [[String: Any]] ?? []
        // Type 0 is a normal desktop; 4 is a full-screen app.
        return spaces.filter { ($0["type"] as? Int) == 0 }
            .compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
    }

    /// The Space a window lives on. Nil for unknown windows and for windows
    /// shown on every Space.
    public static func of(_ window: CGWindowID) -> SpaceID? {
        // Unlike CGWindowListCreateDescriptionFromArray, this call takes CFNumbers.
        let ids = [NSNumber(value: window)] as CFArray
        guard let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), allSpacesMask, ids)?
                .takeRetainedValue() as? [NSNumber],
              spaces.count == 1 else { return nil }
        return spaces[0].uint64Value
    }
}
