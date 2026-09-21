import AppKit
import Foundation

/// A macOS Space (desktop), as the window server numbers it.
public typealias SpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSManagedDisplayGetCurrentSpace")
private func CGSManagedDisplayGetCurrentSpace(_ cid: Int32, _ display: CFString) -> SpaceID

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
