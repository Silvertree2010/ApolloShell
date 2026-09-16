import Foundation

/// Eine Zeile `--name: wert;` aus einer Theme-Datei, noch ungeprueft.
public struct ThemeDeclaration: Equatable, Hashable, Sendable {
    /// Klein geschrieben, mit den zwei Bindestrichen.
    public let name: String
    /// Roher Text nach dem Doppelpunkt, getrimmt.
    public let value: String
    /// Zeile in der Datei, 1-basiert.
    public let line: Int

    public init(name: String, value: String, line: Int) {
        self.name = name
        self.value = value
        self.line = line
    }
}

/// Was in einer Theme-Datei stand: die Angaben aus `:root` und die
/// Abweichungen fuer das dunkle Erscheinungsbild.
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

/// Liest die CSS-Teilmenge, die ein Theme ausmacht. Ohne WebKit, ohne
/// Netzwerk, ohne Ausnahmen nach aussen.
///
/// Verstanden wird:
/// - `:root { --apollo-…: wert; }`
/// - `@media (prefers-color-scheme: dark) { :root { … } }` fuer Abweichungen
/// - Kommentare `/* … */`
///
/// Alles andere wird uebersprungen und als Hinweis vermerkt: fremde
/// Selektoren, andere At-Regeln, `@import`, verschachtelte Bloecke. Damit
/// bleibt eine Datei lesbar, die spaeter einmal mehr enthaelt, als diese
/// Fassung kennt - der Kern nimmt sich nur, was er versteht.
public enum ThemeStyleSheetParser {
    public static func parse(_ text: String, limits: ThemeLimits = .standard) -> ThemeStyleSheet {
        var parser = Parser(text: text, limits: limits)
        parser.run(dark: false, allowMedia: true)
        return ThemeStyleSheet(light: parser.light, dark: parser.dark, issues: parser.log.finished())
    }

    /// Nur die Angabe, die im dunklen Erscheinungsbild gilt. `@media` schlaegt
    /// `:root`, sonst zaehlt die letzte Zeile - wie in CSS.
    public static func effectiveDark(_ sheet: ThemeStyleSheet) -> [ThemeDeclaration] {
        sheet.light + sheet.dark
    }
}

/// Der Scanner. Absichtlich ueber `[Character]` mit ganzzahligem Index: so
/// kostet jeder Schritt gleich viel, auch bei einer halben Megabyte grossen
/// Datei, und Unicode in Namen und Texten bleibt heil.
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
        // `isNewline` statt `== "\n"`: Swift fasst CRLF zu einem einzigen
        // Character zusammen, eine Datei von Windows wuerde sonst durchweg
        // falsche Zeilennummern melden.
        if chars[index].isNewline { line += 1 }
        index += 1
    }

    /// Ein Kommentar oder eine Zeichenkette an dieser Stelle - beides darf
    /// nirgends mitzaehlen, wenn Klammern gepaart werden.
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
                // Ein Zeilenumbruch beendet in CSS eine kaputte Zeichenkette.
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

    /// Ab `{` bis hinter die zugehoerige `}`. Steht dort kein `{`, passiert
    /// nichts.
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
                // Streuzeichen aus einer kaputten Datei.
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

    /// Liest bis `{` oder `;` (was zuerst kommt) und gibt den Text davor
    /// zurueck; der Index steht danach auf dem Zeichen selbst oder am Ende.
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
            // @import und Verwandte: ueberspringen. Ein Theme laedt nie eine
            // zweite Datei - das waere ein Weg nach draussen.
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
        // Den Block einmal abstecken und dann darin dasselbe tun wie oben -
        // hoechstens eine Ebene tief, verschachtelte @media zaehlen nicht.
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
                // Kein Doppelpunkt: entweder Unsinn oder ein verschachtelter
                // Block. Beides ueberspringen.
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
            // Nur eigene Eigenschaften interessieren. `color: red` in :root
            // ist gueltiges CSS fuer eine Webseite und hier bedeutungslos.
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

    /// Wert bis `;` oder bis zur schliessenden `}` der Regel. Klammern,
    /// Zeichenketten und Kommentare zaehlen mit, damit `url("a;b")` heil
    /// bleibt.
    private mutating func readValue() -> String {
        var text = ""
        var depth = 0
        while !isAtEnd {
            let before = index
            if skipCommentOrString() {
                // Kommentar oder Zeichenkette: beim Wert bleibt der Text
                // erhalten, ein Kommentar faellt weg.
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
                // Die letzte Angabe eines Blocks darf das Semikolon weglassen.
                // Die Klammer selbst bleibt stehen: sie schliesst den Block,
                // und wer sie hier verschluckt, liest den Rest der Datei als
                // Fortsetzung von `:root`.
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

    /// Klein geschrieben und ohne jeden Leerraum - fuer den Vergleich von
    /// Selektoren und Bedingungen.
    var condensed: String {
        lowercased().filter { !$0.isWhitespace }
    }
}
