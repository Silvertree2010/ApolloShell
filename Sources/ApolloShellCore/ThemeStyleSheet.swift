import Foundation

/// One line `--name: value;` out of a theme file, not checked yet.
public struct ThemeDeclaration: Equatable, Hashable, Sendable {
    /// In lower case, with the two hyphens.
    public let name: String
    /// The raw text after the colon, trimmed.
    public let value: String
    /// The line in the file, 1-based.
    public let line: Int

    public init(name: String, value: String, line: Int) {
        self.name = name
        self.value = value
        self.line = line
    }
}

/// What stood in a theme file: the entries out of `:root` and the variants
/// for the dark appearance.
public struct ThemeStyleSheet: Equatable, Sendable {
    public var light: [ThemeDeclaration]
    public var dark: [ThemeDeclaration]
    public var issues: [ThemeIssue]

    public init(light: [ThemeDeclaration] = [], dark: [ThemeDeclaration] = [],
                issues: [ThemeIssue] = []) {
        self.light = light
        self.dark = dark
        self.issues = issues
    }
}

/// Reads the CSS subset that makes up a theme. Without WebKit, without the
/// network, without exceptions to the outside.
///
/// Understood are:
/// - `:root { --apollo-…: value; }`
/// - `@media (prefers-color-scheme: dark) { :root { … } }` for the variants
/// - comments `/* … */`
///
/// Everything else is skipped and noted as a notice: foreign selectors, other
/// at-rules, `@import`, nested blocks. That keeps a file readable which one
/// day holds more than this version knows - the core takes only what it
/// understands.
public enum ThemeStyleSheetParser {
    public static func parse(_ text: String, limits: ThemeLimits = .standard) -> ThemeStyleSheet {
        var parser = Parser(text: text, limits: limits)
        parser.run(dark: false, allowMedia: true)
        return ThemeStyleSheet(light: parser.light, dark: parser.dark, issues: parser.log.finished())
    }

    /// Only the entry that holds in the dark appearance. `@media` beats
    /// `:root`, otherwise the last line counts - as in CSS.
    public static func effectiveDark(_ sheet: ThemeStyleSheet) -> [ThemeDeclaration] {
        sheet.light + sheet.dark
    }
}

/// The scanner. Over `[Character]` with an integer index on purpose: that way
/// every step costs the same, even with a file half a megabyte big, and
/// Unicode in names and texts stays whole.
private struct Parser {
    private let chars: [Character]
    private var index: Int
    private var end: Int
    private var line: Int
    private let limits: ThemeLimits

    var light: [ThemeDeclaration] = []
    var dark: [ThemeDeclaration] = []
    var log: ThemeIssueLog
    private var stopped = false

    init(text: String, limits: ThemeLimits) {
        chars = Array(text)
        index = 0
        end = chars.count
        line = 1
        self.limits = limits
        log = ThemeIssueLog(limit: limits.maxIssues)
    }

    private var isAtEnd: Bool { index >= end }

    private mutating func advance() {
        // `isNewline` instead of `== "\n"`: Swift takes CRLF as a single
        // Character, and a file from Windows would otherwise report wrong line
        // numbers throughout.
        if chars[index].isNewline { line += 1 }
        index += 1
    }

    /// A comment or a string at this place - neither may count anywhere when
    /// brackets are paired.
    private mutating func skipCommentOrString() -> Bool {
        guard !isAtEnd else { return false }
        let c = chars[index]
        if c == "/", index + 1 < end, chars[index + 1] == "*" {
            advance()
            advance()
            while !isAtEnd {
                if chars[index] == "*", index + 1 < end, chars[index + 1] == "/" {
                    advance()
                    advance()
                    return true
                }
                advance()
            }
            log.add(.ignoredRule("unterminated comment"), line: line)
            return true
        }
        if c == "\"" || c == "'" {
            let quote = c
            let startLine = line
            advance()
            while !isAtEnd {
                let current = chars[index]
                // A line break ends a broken string in CSS.
                if current.isNewline {
                    log.add(.ignoredRule("unterminated string"), line: startLine)
                    return true
                }
                if current == "\\", index + 1 < end {
                    advance()
                    advance()
                    continue
                }
                advance()
                if current == quote { return true }
            }
            log.add(.ignoredRule("unterminated string"), line: startLine)
            return true
        }
        return false
    }

    private mutating func skipTrivia() {
        while !isAtEnd {
            if chars[index].isWhitespace {
                advance()
                continue
            }
            if chars[index] == "/", index + 1 < end, chars[index + 1] == "*" {
                _ = skipCommentOrString()
                continue
            }
            return
        }
    }

    /// From `{` to past the matching `}`. When no `{` stands there, nothing
    /// happens.
    private mutating func skipBlock() {
        guard !isAtEnd, chars[index] == "{" else { return }
        var depth = 0
        while !isAtEnd {
            if skipCommentOrString() { continue }
            let c = chars[index]
            if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                advance()
                if depth <= 0 { return }
                continue
            }
            advance()
        }
    }

    mutating func run(dark: Bool, allowMedia: Bool) {
        while !isAtEnd, !stopped {
            skipTrivia()
            if isAtEnd { return }
            let c = chars[index]
            if c == "}" || c == ";" {
                // Stray characters out of a broken file.
                advance()
                continue
            }
            if c == "@" {
                atRule(dark: dark, allowMedia: allowMedia)
                continue
            }
            ruleSet(dark: dark)
        }
    }

    /// Reads up to `{` or `;` (whichever comes first) and hands back the text
    /// before it; the index then stands on that character itself or at the end.
    private mutating func readPrelude() -> String {
        var text = ""
        while !isAtEnd {
            let before = index
            if skipCommentOrString() {
                text += String(chars[before..<index])
                continue
            }
            let c = chars[index]
            if c == "{" || c == ";" { return text }
            text.append(c)
            advance()
        }
        return text
    }

    private mutating func atRule(dark: Bool, allowMedia: Bool) {
        let startLine = line
        advance() // @
        var name = ""
        while !isAtEnd, chars[index].isLetter || chars[index] == "-" {
            name.append(chars[index])
            advance()
        }
        let prelude = readPrelude()
        let rule = "@" + name + " " + prelude.trimmedText
        if isAtEnd {
            log.add(.ignoredRule(rule.trimmedText), line: startLine)
            return
        }
        if chars[index] == ";" {
                // @import and relatives: skip. A theme never loads a second
                // file - that would be a way out.
            advance()
            log.add(.ignoredRule(rule.trimmedText), line: startLine)
            return
        }
        let wantsDark = name.lowercased() == "media" && prelude.condensed == "(prefers-color-scheme:dark)"
        guard allowMedia, wantsDark else {
            log.add(.ignoredRule(rule.trimmedText), line: startLine)
            skipBlock()
            return
        }
                // Mark the block out once and then do the same in it as above
                // - one level deep at most, nested @media does not count.
        let open = index
        skipBlock()
        let close = index
        let lineAfter = line
        let inner = close > open && chars[close - 1] == "}" ? close - 1 : close
        let savedEnd = end
        index = open + 1
        end = inner
        line = startLine
        run(dark: true, allowMedia: false)
        index = close
        end = savedEnd
        line = lineAfter
    }

    private mutating func ruleSet(dark: Bool) {
        let startLine = line
        let prelude = readPrelude()
        guard !isAtEnd else {
            log.add(.ignoredRule("selector without a block: " + prelude.trimmedText), line: startLine)
            return
        }
        if chars[index] == ";" {
            advance()
            log.add(.ignoredRule(prelude.trimmedText), line: startLine)
            return
        }
        guard prelude.condensed == ":root" else {
            log.add(.ignoredRule("selector " + prelude.trimmedText), line: startLine)
            skipBlock()
            return
        }
        declarations(dark: dark)
    }

    private mutating func declarations(dark: Bool) {
        advance() // {
        while !isAtEnd {
            skipTrivia()
            if isAtEnd { return }
            if chars[index] == "}" {
                advance()
                return
            }
            if chars[index] == ";" {
                advance()
                continue
            }
            let startLine = line
            var name = ""
            var sawColon = false
            while !isAtEnd {
                if skipCommentOrString() { continue }
                let c = chars[index]
                if c == ":" {
                    sawColon = true
                    advance()
                    break
                }
                if c == ";" || c == "}" || c == "{" { break }
                name.append(c)
                advance()
            }
            guard sawColon else {
                // No colon: either nonsense or a nested block. Skip both.
                //
                if !isAtEnd, chars[index] == "{" {
                    log.add(.ignoredRule("nested block"), line: startLine)
                    skipBlock()
                    continue
                }
                if !isAtEnd, chars[index] == ";" {
                    advance()
                    if !name.trimmedText.isEmpty { log.add(.ignoredRule(name.trimmedText), line: startLine) }
                    continue
                }
                if !isAtEnd, chars[index] == "}" {
                    advance()
                    return
                }
                return
            }
            let value = readValue()
            let key = name.trimmedText.lowercased()
            // Only custom properties are of interest. `color: red` in :root is
            // valid CSS for a web page and meaningless here.
            guard key.hasPrefix("--") else { continue }
            guard light.count + self.dark.count < limits.maxDeclarations else {
                log.add(.tooManyDeclarations(limit: limits.maxDeclarations), line: startLine)
                stopped = true
                index = end
                return
            }
            let declaration = ThemeDeclaration(name: key, value: value.trimmedText, line: startLine)
            if dark { self.dark.append(declaration) } else { light.append(declaration) }
        }
    }

    /// The value up to `;` or up to the closing `}` of the rule. Brackets,
    /// strings and comments count in, so that `url("a;b")` stays whole.
    /// bleibt.
    private mutating func readValue() -> String {
        var text = ""
        var depth = 0
        while !isAtEnd {
            let before = index
            if skipCommentOrString() {
                // A comment or a string: in the value the text is kept, a
                // comment falls away.
                let chunk = String(chars[before..<index])
                if chunk.hasPrefix("/*") { text += " " } else { text += chunk }
                continue
            }
            let c = chars[index]
            if c == "(" { depth += 1 }
            if c == ")" { depth = max(depth - 1, 0) }
            if depth == 0, c == ";" {
                advance()
                return text
            }
            if depth == 0, c == "}" {
                // The last entry of a block may leave out the semicolon. The
                // bracket itself stays standing: it closes the block, and
                // whoever swallows it here reads the rest of the file as a
                // continuation of `:root`.
                return text
            }
            text.append(c)
            advance()
        }
        return text
    }
}

extension String {
    var trimmedText: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// In lower case and without any whitespace - for comparing selectors and
    /// conditions.
    var condensed: String {
        lowercased().filter { !$0.isWhitespace }
    }
}
