import Foundation

/// Self-updating (Nexus > Updates).
///
/// Both defaults are on on purpose: whoever downloads the app should get the
/// next version without doing anything. So Sparkle does not ask on the first
/// start either - the choice stands visibly in Nexus instead, and the README
/// and the introduction say so.
///
/// It is installed on quit. Because the shell is practically never quit, Nexus
/// also shows "Restart now" as soon as something lies ready.
///
/// For a Homebrew installation neither switch holds (see `InstallKind`); there
/// it only reports.
public struct UpdateSettings: Codable, Equatable, Sendable {
    /// Look in the background every day whether there is something new.
    public var checkAutomatically: Bool
    /// Download found updates without asking and install them on quit.
    public var installAutomatically: Bool
    /// When it last looked. Only the Homebrew build writes that down; with the
    /// DMG build Sparkle keeps the books itself.
    public var lastCheck: Date?

    public init(checkAutomatically: Bool = true, installAutomatically: Bool = true, lastCheck: Date? = nil) {
        self.checkAutomatically = checkAutomatically
        self.installAutomatically = installAutomatically
        self.lastCheck = lastCheck
    }

    private enum CodingKeys: String, CodingKey {
        case checkAutomatically, installAutomatically, lastCheck
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.checkAutomatically, into: &checkAutomatically)
        c.lenient(.installAutomatically, into: &installAutomatically)
        c.lenient(.lastCheck, into: &lastCheck)
    }
}

/// The chosen theme (Nexus > Themes).
///
/// Only the file name in the theme folder is stored ("Midnight.css" or
/// "Midnight" as a folder), not the whole path: that way the setting stays
/// valid when the folder moves, and nobody can point at a path outside the
/// theme folder through the file.
public struct ThemeSettings: Codable, Equatable, Sendable {
    /// The name in the theme folder; `nil` = none, and it looks untouched.
    public var name: String?

    public init(name: String? = nil) {
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case name
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let stored: String? = c.lenient(.name)
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // A path part would be a way out of the folder; then rather none.
        name = (trimmed.isEmpty || trimmed.contains("/") || trimmed.hasPrefix(".")) ? nil : trimmed
    }

    /// Write `name` as `null` even without a value, as with `providers`.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
    }
}
