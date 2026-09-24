import Foundation

/// Apple's menu bar hidden while the shell's menu bar stands in its place:
/// `_HIHideMenuBar` in the global domain (what "Automatically hide and show
/// the menu bar" writes) plus the notification that makes running apps
/// follow at once - measured 22.09. in the VM, no restart needed.
///
/// Pure like `AppleDockHiding`: the values and decisions, the controller
/// (AppleMenuBarHidingController) does the writing. The value from before is
/// saved to apple-menubar.json, so a crash leaves a way back: the next start
/// restores it unless the setting still wants the bar hidden.
public enum AppleMenuBarHiding {
    public static let key = "_HIHideMenuBar"
    public static let notification = "AppleInterfaceMenuBarHidingChangedNotification"

    /// Hide only while our bar is really there: switched on, with modules,
    /// and the setting on. Otherwise nothing would be left at the top.
    public static func shouldHide(_ bar: ApolloMenuBar) -> Bool {
        bar.isActive && bar.hideAppleMenuBar
    }
}

/// The value of `_HIHideMenuBar` before the shell touched it. `hidden` is
/// `nil` when the key was missing - it is removed again then, not written as
/// `false`. Unlike the Dock's keys, `true` is a legitimate original: the user
/// may hide the menu bar himself, and gets exactly that back.
public struct AppleMenuBarOriginal: Codable, Equatable, Sendable {
    public var hidden: Bool?

    public init(hidden: Bool? = nil) {
        self.hidden = hidden
    }

    /// `nil` when the file is missing (nothing hidden by the shell) or
    /// unreadable.
    public static func load(from data: Data?) -> AppleMenuBarOriginal? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(AppleMenuBarOriginal.self, from: data)
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}
