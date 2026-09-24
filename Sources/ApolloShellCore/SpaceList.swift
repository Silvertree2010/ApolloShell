import Foundation

public struct SpaceSnapshot: Equatable, Sendable {
    public var desktops: [UInt64]
    public var activeIndex: Int?

    public init(desktops: [UInt64], activeIndex: Int?) {
        self.desktops = desktops
        self.activeIndex = activeIndex
    }
}

public enum SpaceList {
    public static let desktopType = 0
    public static let fullscreenType = 4
    public static let sharedDisplayIdentifier = "Main"

    public static func snapshot(displays: [[String: Any]], mainDisplay: String?) -> SpaceSnapshot? {
        guard let display = pickDisplay(displays, mainDisplay: mainDisplay),
              let spaces = display["Spaces"] as? [[String: Any]]
        else { return nil }
        let desktops = spaces.compactMap { space -> UInt64? in
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

    static func spaceType(_ space: [String: Any], in display: [String: Any]) -> Int? {
        if let type = (space["type"] as? NSNumber)?.intValue { return type }
        guard let id = spaceID(space),
              let spaces = display["Spaces"] as? [[String: Any]],
              let match = spaces.first(where: { spaceID($0) == id })
        else { return nil }
        return (match["type"] as? NSNumber)?.intValue
    }

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
