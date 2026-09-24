import AppKit
import Foundation

public typealias SpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSManagedDisplayGetCurrentSpace")
private func CGSManagedDisplayGetCurrentSpace(_ cid: Int32, _ display: CFString) -> SpaceID

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> Unmanaged<CFArray>?

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> Unmanaged<CFArray>?

public enum Spaces {
    private static let allSpacesMask: Int32 = 0x7

    public static func current() -> SpaceID? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue(),
              let name = CFUUIDCreateString(nil, uuid) else { return nil }
        let space = CGSManagedDisplayGetCurrentSpace(CGSMainConnectionID(), name)
        return space == 0 ? nil : space
    }

    public static func ordered() -> [SpaceID] {
        guard let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue()
                as? [[String: Any]] else { return [] }
        let main = current()
        let display = displays.first { ($0["Spaces"] as? [[String: Any]])?.contains {
            ($0["id64"] as? NSNumber)?.uint64Value == main } ?? false } ?? displays.first
        let spaces = display?["Spaces"] as? [[String: Any]] ?? []
        return spaces.filter { ($0["type"] as? Int) == 0 }
            .compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
    }

    public struct Display: Sendable, Equatable {
        public let uuid: String
        public let current: SpaceID
        public let desktops: [SpaceID]
    }

    public static func displays() -> [Display] {
        guard let raw = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue()
                as? [[String: Any]] else { return [] }
        return raw.compactMap { entry in
            guard let uuid = entry["Display Identifier"] as? String,
                  let current = ((entry["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.uint64Value
            else { return nil }
            let spaces = entry["Spaces"] as? [[String: Any]] ?? []
            let desktops = spaces.filter { ($0["type"] as? Int) == 0 }
                .compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
            return Display(uuid: uuid, current: current, desktops: desktops)
        }
    }

    @MainActor
    public static func uuid(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    public static func of(_ window: CGWindowID) -> SpaceID? {
        let ids = [NSNumber(value: window)] as CFArray
        guard let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), allSpacesMask, ids)?
                .takeRetainedValue() as? [NSNumber],
              spaces.count == 1 else { return nil }
        return spaces[0].uint64Value
    }
}
