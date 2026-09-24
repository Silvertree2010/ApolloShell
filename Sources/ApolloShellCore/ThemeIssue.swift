import Foundation

public struct ThemeIssue: Equatable, Hashable, Sendable, CustomStringConvertible {
    public enum Kind: Equatable, Hashable, Sendable {
        case unknownToken(String)
        case unknownIcon(String)
        case unreadableValue(token: String, value: String)
        case clamped(token: String, value: String, used: String)
        case contrastAdjusted(token: String, requested: String, used: String, dark: Bool)
        case ignoredRule(String)
        case rejectedAsset(reference: String, reason: ThemeAssetRejection)
        case newerFormat(found: Int, known: Int)
        case styleSheetTooLarge(bytes: Int, limit: Int)
        case notText
        case notUTF8
        case unreadableFile(String)
        case tooManyDeclarations(limit: Int)
        case moreIssues(dropped: Int)
    }

    public let kind: Kind
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

public enum ThemeAssetRejection: Error, Equatable, Hashable, Sendable, CustomStringConvertible {
    case escapesFolder
    case notALocalPath
    case outsideThemeFolder
    case needsThemeFolder
    case missing
    case tooLarge(bytes: Int, limit: Int)
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

    func finished() -> [ThemeIssue] {
        dropped == 0 ? issues : issues + [ThemeIssue(.moreIssues(dropped: dropped))]
    }
}
