import Foundation

/// What stood out while a theme was read.
///
/// A notice is never an error: the theme always loads, with the defaults if
/// need be. The notices are for whoever writes the theme - Nexus shows them
/// later.
///
/// Data on purpose, never a finished sentence: the user interface words
/// it itself. `description` is English and meant for logs and tests, not
/// for the window.
///
public struct ThemeIssue: Equatable, Hashable, Sendable, CustomStringConvertible {
    public enum Kind: Equatable, Hashable, Sendable {
        /// `--apollo-…`, but no token this version knows. A theme out of a
        /// later version looks exactly like this - so this is only a notice,
        /// never an error.
        case unknownToken(String)
        /// A file in `icons/` whose name is no symbol id of this version.
        /// Only a notice, as with an unknown token.
        case unknownIcon(String)
        /// The value does not fit the type of the token. The default applies
        /// (or the last readable value of the same token).
        case unreadableValue(token: String, value: String)
        /// The value lay outside the allowed range and was clamped.
        case clamped(token: String, value: String, used: String)
        /// The text color was unreadable on its background and was lightened
        /// or darkened. `dark` says in which appearance - a light text color
        /// without a dark variant of its own only stands out in the dark
        /// one.
        case contrastAdjusted(token: String, requested: String, used: String, dark: Bool)
        /// A line that does not belong to the supported CSS subset.
        case ignoredRule(String)
        /// A file that may not be used (the path leads outside, too big,
        /// missing, the wrong kind).
        case rejectedAsset(reference: String, reason: ThemeAssetRejection)
        /// The theme names a higher format number than this version knows.
        case newerFormat(found: Int, known: Int)
        /// The file is bigger than allowed and was not read at all.
        case styleSheetTooLarge(bytes: Int, limit: Int)
        /// No text (null bytes) - probably an image file by mistake.
        case notText
        /// No valid UTF-8; read as Latin-1, so that at least the ASCII lines
        /// arrive.
        case notUTF8
        /// The file or folder could not be read.
        case unreadableFile(String)
        /// More lines than a style sheet may have; the rest of them was
        /// skipped.
        case tooManyDeclarations(limit: Int)
        /// There were more notices; they are only collected up to the limit.
        case moreIssues(dropped: Int)
    }

    public let kind: Kind
    /// The line in the CSS file, 1-based. `nil` when there is no line (the
    /// file is too big, the folder unreadable).
    public let line: Int?

    public init(_ kind: Kind, line: Int? = nil) {
        self.kind = kind
        self.line = line
    }

    public var description: String {
        let place = line.map { "line \($0): " } ?? ""
        return place + text
    }

    private var text: String {
        switch kind {
        case let .unknownToken(name):
            "unknown token \(name), ignored"
        case let .unknownIcon(name):
            "unknown icon \(name), ignored"
        case let .unreadableValue(token, value):
            "cannot read value \"\(value)\" for \(token), using the default"
        case let .clamped(token, value, used):
            "\(token) value \(value) is out of range, using \(used)"
        case let .contrastAdjusted(token, requested, used, dark):
            "\(token) \(requested) was unreadable on its background"
                + (dark ? " in dark mode" : "") + ", using \(used)"
        case let .ignoredRule(rule):
            "ignored: \(rule)"
        case let .rejectedAsset(reference, reason):
            "file \"\(reference)\" rejected: \(reason.description)"
        case let .newerFormat(found, known):
            "theme format \(found) is newer than \(known); unknown parts are ignored"
        case let .styleSheetTooLarge(bytes, limit):
            "style sheet is \(bytes) bytes, the limit is \(limit)"
        case .notText:
            "not a text file"
        case .notUTF8:
            "not valid UTF-8, read as Latin-1"
        case let .unreadableFile(path):
            "cannot read \(path)"
        case let .tooManyDeclarations(limit):
            "more than \(limit) declarations, the rest was skipped"
        case let .moreIssues(dropped):
            "and \(dropped) more"
        }
    }
}

/// Why a file out of a theme is not used. The first four reasons are
/// security: a theme may only read out of its own folder.
public enum ThemeAssetRejection: Error, Equatable, Hashable, Sendable, CustomStringConvertible {
    /// `..`, an absolute path or `~` - points out of the folder.
    case escapesFolder
    /// `http:`, `file:`, `data:` and everything else with a scheme.
    case notALocalPath
    /// After resolving links the file lies outside.
    case outsideThemeFolder
    /// A single-file .css theme has no folder of its own and therefore no
    /// files - whoever wants images makes a folder with theme.css in it.
    case needsThemeFolder
    /// Does not exist or is no ordinary file.
    case missing
    /// Bigger than allowed.
    case tooLarge(bytes: Int, limit: Int)
    /// None of the allowed image extensions.
    case unsupportedType(String)

    public var description: String {
        switch self {
        case .escapesFolder: "the path leaves the theme folder"
        case .notALocalPath: "only relative paths inside the theme folder are allowed"
        case .outsideThemeFolder: "the resolved path is outside the theme folder"
        case .needsThemeFolder: "single-file themes cannot ship images"
        case .missing: "no such file"
        case let .tooLarge(bytes, limit): "\(bytes) bytes, the limit is \(limit)"
        case let .unsupportedType(ext): "\(ext.isEmpty ? "no" : "." + ext) is not a supported image type"
        }
    }
}

/// Collects notices and stops at a limit - a file of random bytes should not
/// write thousands of notices into memory.
struct ThemeIssueLog {
    private(set) var issues: [ThemeIssue] = []
    private var dropped = 0
    let limit: Int

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    mutating func add(_ kind: ThemeIssue.Kind, line: Int? = nil) {
        guard issues.count < limit else {
            dropped += 1
            return
        }
        issues.append(ThemeIssue(kind, line: line))
    }

    mutating func append(contentsOf others: [ThemeIssue]) {
        for issue in others {
            guard issues.count < limit else {
                dropped += 1
                continue
            }
            issues.append(issue)
        }
    }

    /// At the end: the collected notices, with a note of how many are
    /// missing if need be.
    func finished() -> [ThemeIssue] {
        dropped == 0 ? issues : issues + [ThemeIssue(.moreIssues(dropped: dropped))]
    }
}
