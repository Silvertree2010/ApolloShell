import Foundation

public struct RawMenuItem: Equatable, Sendable {
    public let title: String
    public let enabled: Bool
    public let mark: String
    public let hasSubmenu: Bool
    public let children: [RawMenuItem]

    public init(title: String, enabled: Bool = true, mark: String = "",
                hasSubmenu: Bool = false, children: [RawMenuItem] = []) {
        self.title = title
        self.enabled = enabled
        self.mark = mark
        self.hasSubmenu = hasSubmenu
        self.children = children
    }
}

public struct DockMenuStep: Equatable, Sendable {
    public let title: String
    public let index: Int

    public init(title: String, index: Int) {
        self.title = title
        self.index = index
    }
}

public struct DockMenuNode: Equatable, Sendable {
    public let title: String
    public let enabled: Bool
    public let checked: Bool
    public let separator: Bool
    public let path: [DockMenuStep]
    public let children: [DockMenuNode]

    public init(title: String, enabled: Bool, checked: Bool, separator: Bool,
                path: [DockMenuStep], children: [DockMenuNode]) {
        self.title = title
        self.enabled = enabled
        self.checked = checked
        self.separator = separator
        self.path = path
        self.children = children
    }
}

public enum DockMenuTree {
    public static let maximumDepth = 2

    public static func nodes(from items: [RawMenuItem], path: [DockMenuStep] = [], depth: Int = 0) -> [DockMenuNode] {
        guard depth < maximumDepth else { return [] }
        return items.enumerated().map { index, item in
            let separator = item.title.trimmingCharacters(in: .whitespaces).isEmpty && !item.hasSubmenu
            let ownPath = path + [DockMenuStep(title: item.title, index: index)]
            return DockMenuNode(
                title: item.title,
                enabled: item.enabled,
                checked: !item.mark.isEmpty,
                separator: separator,
                path: ownPath,
                children: item.hasSubmenu ? nodes(from: item.children, path: ownPath, depth: depth + 1) : []
            )
        }
    }

    public static func isKeepInDock(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed == "im dock behalten" || trimmed == "keep in dock"
    }
}
