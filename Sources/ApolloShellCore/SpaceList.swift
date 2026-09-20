import Foundation

/// The spaces of the main screen, the way the bar shows them.
public struct SpaceSnapshot: Equatable, Sendable {
    /// The ids of the desktops in Mission Control order.
    public var desktops: [UInt64]
    /// The place of the active desktop in `desktops`. `nil` when a full-screen
    /// space is active right now - then the bar is gone anyway (WindowGuard
    /// hides it).
    public var activeIndex: Int?

    public init(desktops: [UInt64], activeIndex: Int?) {
        self.desktops = desktops
        self.activeIndex = activeIndex
    }
}

/// Reads the space list of SkyLight.
///
/// macOS has no public interface for spaces. The data comes out of
/// `CGSCopyManagedDisplaySpaces` (private, read-only, without a permission;
/// the call stands in SpacesModel.swift). Only the reading is here, so that it
/// is testable without a WindowServer.
///
/// The shape, measured on 14.09. on macOS 26.6: one dictionary per screen with
/// "Display Identifier" (the UUID of the screen; "Main" when "Displays have
/// separate Spaces" is off), "Spaces" and "Current Space". Every space has
/// "id64" and "ManagedSpaceID" (the same number) and "type". The list stands
/// in Mission Control order, not sorted by id: measured, space 3 came before
/// space 1.
public enum SpaceList {
    /// An ordinary desktop.
    public static let desktopType = 0
    /// A full-screen app (Split View too).
    public static let fullscreenType = 4
    /// The id when all screens share the spaces.
    public static let sharedDisplayIdentifier = "Main"

    /// The bar does not show full-screen spaces: Mission Control only numbers
    /// the desktops ("Desktop 1...n"), Ctrl+number only jumps to them, and in
    /// a full-screen space the bar is hidden - a dot for it could never be
    /// seen as active.
    ///
    /// `nil` when nothing usable stands in it; then the bar shows no capsule
    /// instead of a wrong one.
    public static func snapshot(displays: [[String: Any]], mainDisplay: String?) -> SpaceSnapshot? {
        guard let display = pickDisplay(displays, mainDisplay: mainDisplay),
              let spaces = display["Spaces"] as? [[String: Any]]
        else { return nil }
        let desktops = spaces.compactMap { space -> UInt64? in
            // Without "type" do not guess: one dot too few rather than a wrong one.
            guard (space["type"] as? NSNumber)?.intValue == desktopType else { return nil }
            return spaceID(space)
        }
        guard !desktops.isEmpty else { return nil }
        let current = (display["Current Space"] as? [String: Any]).flatMap(spaceID)
        return SpaceSnapshot(
            desktops: desktops,
            activeIndex: current.flatMap { desktops.firstIndex(of: $0) }
        )
    }

    /// The ids (in capitals) of the screens whose active space shows a
    /// full-screen app. The bar steps aside there.
    ///
    /// What is asked is the space itself, not the foreground app: a
    /// full-screen video on one screen stays full screen even when the focus
    /// lies on a window of the other one.
    ///
    /// `nil` when no screen can be read; then the old state stays.
    /// "Main" stands for all screens (shared spaces).
    public static func fullscreenDisplays(_ displays: [[String: Any]]) -> Set<String>? {
        var result: Set<String> = []
        var readable = false
        for display in displays {
            guard let identifier = display["Display Identifier"] as? String,
                  let current = display["Current Space"] as? [String: Any]
            else { continue }
            readable = true
            if spaceType(current, in: display) == fullscreenType {
                result.insert(identifier.uppercased())
            }
        }
        return readable ? result : nil
    }

    /// The type of the space; when it is missing on the entry itself, out of
    /// the list of the screen by id.
    static func spaceType(_ space: [String: Any], in display: [String: Any]) -> Int? {
        if let type = (space["type"] as? NSNumber)?.intValue { return type }
        guard let id = spaceID(space),
              let spaces = display["Spaces"] as? [[String: Any]],
              let match = spaces.first(where: { spaceID($0) == id })
        else { return nil }
        return (match["type"] as? NSNumber)?.intValue
    }

    /// The screen with the menu bar (that is where the bar stands): by UUID,
    /// otherwise the shared "Main", otherwise the first one.
    static func pickDisplay(_ displays: [[String: Any]], mainDisplay: String?) -> [String: Any]? {
        func identifier(_ display: [String: Any]) -> String? { display["Display Identifier"] as? String }
        if let mainDisplay,
           let match = displays.first(where: { identifier($0)?.caseInsensitiveCompare(mainDisplay) == .orderedSame }) {
            return match
        }
        if let shared = displays.first(where: { identifier($0) == sharedDisplayIdentifier }) {
            return shared
        }
        return displays.first
    }

    static func spaceID(_ space: [String: Any]) -> UInt64? {
        ((space["id64"] ?? space["ManagedSpaceID"]) as? NSNumber)?.uint64Value
    }
}
