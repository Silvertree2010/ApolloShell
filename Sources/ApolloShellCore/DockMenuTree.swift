import Foundation

/// A menu entry the way the accessibility API reports it - raw, without
/// interpretation.
///
/// The user interface layer reads these entries out of Apple's Dock; what
/// becomes of them is decided by `DockMenuTree` here in the core, so that it
/// can be checked without opening a menu.
public struct RawMenuItem: Equatable, Sendable {
    public let title: String
    public let enabled: Bool
    /// The mark the entry carries (Apple puts a tick on the frontmost window);
    /// empty when it is unmarked.
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

/// One step on the way to a menu entry: the title and the place it stands at
/// in its menu.
///
/// The place belongs with it because titles repeat: two windows of the same
/// document, two recent files of the same name. Searching by the title alone
/// would then press the wrong entry.
public struct DockMenuStep: Equatable, Sendable {
    public let title: String
    public let index: Int

    public init(title: String, index: Int) {
        self.title = title
        self.index = index
    }
}

/// A finished entry for our menu.
public struct DockMenuNode: Equatable, Sendable {
    public let title: String
    public let enabled: Bool
    /// Show it with a tick.
    public let checked: Bool
    public let separator: Bool
    /// The way through the titles up to here. With it the entry is found again
    /// in Apple's menu when that is opened once more to carry it out - the
    /// elements themselves only hold while it is open.
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

/// Makes our menu tree out of what stands in Apple's Dock menu.
public enum DockMenuTree {
    /// It is not read deeper than this. Apple's Dock menu has one level of
    /// submenu ("Options"); everything below that would be foreign ground.
    public static let maximumDepth = 2

    public static func nodes(from items: [RawMenuItem], path: [DockMenuStep] = [], depth: Int = 0) -> [DockMenuNode] {
        guard depth < maximumDepth else { return [] }
        return items.enumerated().map { index, item in
            // Apple reports separators as an entry without a title and without a submenu.
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

    /// The entry that pins in Apple's Dock - in the languages the shell speaks
    /// itself.
    ///
    /// Why it has a special role: it would pin in **Apple's** Dock, which is
    /// hidden while the shell runs. Our menu therefore hooks it over to our own
    /// Dock. When none of the names fits, Apple's behavior stays - an entry
    /// that does something other than expected rather than a menu it is missing
    /// from.
    public static func isKeepInDock(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed == "im dock behalten" || trimmed == "keep in dock"
    }
}
