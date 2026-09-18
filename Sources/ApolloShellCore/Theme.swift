import Foundation

/// Die Formatnummer, die diese Fassung der App kennt.
///
/// Ein Theme nennt sie in `--apollo-theme-format`. Nennt es eine hoehere,
/// wird es trotzdem geladen: gelesen wird, was diese Fassung versteht,
/// unbekannte Token werden uebersprungen und als Hinweis gemeldet. Abgelehnt
/// wird nie - sonst waere ein Theme aus der Zukunft unbrauchbar, statt nur
/// anders auszusehen. Die Nummer steigt nur, wenn sich die Bedeutung eines
/// vorhandenen Tokens aendert; dazukommende Token aendern sie nicht.
public enum ThemeFormat {
    public static let current = 1
}

public extension ThemeTokenCatalog {
    /// Nur Namen mit diesem Anfang gehoeren uns. Alles andere (`--my-blue`)
    /// ist der Namensraum dessen, der das Theme schreibt, und wird stumm
    /// uebergangen.
    static let prefix = "--apollo-"
}

/// Ein fertig gelesenes Theme: die Werte, die in der Datei stehen, hell und
/// dunkel, schon geklemmt und auf Lesbarkeit geprueft.
///
/// Es gibt keinen Weg, an einen ungeprueften Wert zu kommen. Was die Datei
/// nicht nennt, fehlt hier auch (`nil`) - "was du nicht setzt, bleibt wie es
/// ist": Die Vorgaben im Verzeichnis sind dem Aussehen der Shell nur
/// nachempfunden, wer sie einsetzte, aenderte doch etwas (etwa die Breite der
/// Leiste). Den Rueckfall waehlt die App, meist die Systemfarbe von macOS.
public struct Theme: Equatable, Sendable {
    /// Ordner- oder Dateiname ohne `.css`. Bleibt gleich, solange die Datei
    /// gleich heisst - daran haengen spaeter die Einstellung "welches Theme"
    /// und der Eintrag auf der Webseite.
    public let identifier: String
    /// Kleingeschriebene Fassung der Kennung fuer Adressen und Dateinamen.
    public let slug: String
    /// Was in `--apollo-theme-format` stand.
    public let formatVersion: Int
    /// Alles, was beim Lesen aufgefallen ist. Nie ein Grund, das Theme nicht
    /// zu benutzen.
    public let issues: [ThemeIssue]
    /// Nur die genannten Token. Hell: was in `:root` steht; dunkel: dazu,
    /// was der `@media`-Block ueberschreibt oder ergaenzt.
    public let lightValues: [String: ThemeValue]
    public let darkValues: [String: ThemeValue]
    /// Die Bilder aus `icons/`, wenn das Theme ein Ordner ist.
    public let icons: ThemeIconSet

    init(identifier: String, formatVersion: Int, issues: [ThemeIssue],
         lightValues: [String: ThemeValue], darkValues: [String: ThemeValue],
         icons: ThemeIconSet = .none) {
        let name = Theme.cleanIdentifier(identifier)
        self.identifier = name
        slug = Theme.slug(from: name)
        self.formatVersion = formatVersion
        self.issues = issues
        self.lightValues = lightValues
        self.darkValues = darkValues
        self.icons = icons
    }

    /// Das eingebaute Aussehen: kein Wert, kein Hinweis - die Shell, wie sie
    /// ohne Theme aussieht. Auch der Rueckfall, wenn eine Datei unbrauchbar ist.
    public static let standard = Theme.make(identifier: "default", styleSheet: ThemeStyleSheet())

    // MARK: - Werte lesen

    public func value(_ name: String, dark: Bool = false) -> ThemeValue? {
        (dark ? darkValues : lightValues)[name.lowercased()]
    }

    /// Der Wert eines Tokens, wie ihn die Datei nennt - `nil`, wenn sie es
    /// in diesem Erscheinungsbild nicht tut.
    public func value<Kind>(_ token: ThemeToken<Kind>, dark: Bool = false) -> Kind.Value? {
        value(token.name, dark: dark).flatMap(Kind.value(from:))
    }

    /// Nennt das Theme dieses Token ueberhaupt (hell oder dunkel)?
    public func declares(_ name: String) -> Bool {
        value(name) != nil || value(name, dark: true) != nil
    }

    /// Die gepruefte Datei - `nil`, wenn keine angegeben war oder sie nicht
    /// benutzt werden darf.
    public func file(_ token: ThemeFileToken, dark: Bool = false) -> URL? {
        value(token, dark: dark)?.url
    }

    /// Eine Schriftfarbe, auch wenn das Theme nur ihren Untergrund nennt:
    /// dann die Vorgabe, so weit verschoben, bis sie darauf lesbar ist. Nennt
    /// es weder die Farbe noch den Untergrund: `nil`, die App bleibt bei der
    /// Farbe von macOS - die passt dann ja zum Untergrund von macOS.
    public func readableColor(_ token: ThemeColorToken, dark: Bool = false) -> ThemeColor? {
        if let color = value(token, dark: dark) { return color }
        guard let rule = token.descriptor?.contrast,
              let background = value(rule.background, dark: dark)?.color
        else { return nil }
        return ThemeGuards.readable(token.defaultValue(dark: dark), on: background, minimum: rule.minimum)
    }

    /// Das Bild, das dieses Theme fuer ein Symbol mitbringt - `nil`, wenn
    /// keines dabei ist. Dann gilt das eingebaute SF Symbol.
    public func icon(_ id: String) -> URL? {
        icons.file(id)
    }

    /// Was in der Liste steht: der Name aus dem Theme, sonst die Kennung.
    public var title: String {
        let name = value(ThemeTextToken.themeName) ?? ""
        return name.isEmpty ? identifier : name
    }

    public var author: String { value(ThemeTextToken.author) ?? "" }
    public var details: String { value(ThemeTextToken.themeDescription) ?? "" }

    // MARK: - Bauen

    /// Aus gelesenen Angaben ein Theme machen. Kann nicht scheitern.
    ///
    /// Die Angaben aus `:root` gelten in beiden Erscheinungsbildern; der
    /// `@media`-Block legt sich nur darueber - wie in CSS. Was fehlt, bleibt
    /// leer; nur die Kontrastpruefung misst dann am Untergrund aus dem
    /// Verzeichnis.
    public static func make(identifier: String,
                            styleSheet: ThemeStyleSheet,
                            assets: ThemeAssetResolver = .none,
                            catalog: ThemeTokenCatalog = .standard,
                            limits: ThemeLimits = .standard,
                            issues: [ThemeIssue] = [],
                            icons: ThemeIconSet = .none) -> Theme {
        var log = ThemeIssueLog(limit: limits.maxIssues)
        log.append(contentsOf: issues)
        log.append(contentsOf: styleSheet.issues)
        var cache: [String: ThemeAssetOutcome] = [:]
        let light = apply(styleSheet.light, catalog: catalog, limits: limits,
                          assets: assets, cache: &cache, log: &log)
        let dark = apply(styleSheet.dark, catalog: catalog, limits: limits,
                         assets: assets, cache: &cache, log: &log)
        var lightValues = light
        var darkValues = light.merging(dark) { _, new in new }
        ThemeGuards.enforceContrast(in: &lightValues, catalog: catalog, dark: false, log: &log)
        ThemeGuards.enforceContrast(in: &darkValues, catalog: catalog, dark: true, log: &log)
        let format = Int(lightValues[ThemeNumberToken.format.name]?.number ?? Double(ThemeFormat.current))
        if format > ThemeFormat.current {
            log.add(.newerFormat(found: format, known: ThemeFormat.current))
        }
        return Theme(identifier: identifier, formatVersion: format,
                     issues: withoutDuplicates(log.finished()),
                     lightValues: lightValues, darkValues: darkValues, icons: icons)
    }

    private static func apply(_ declarations: [ThemeDeclaration],
                              catalog: ThemeTokenCatalog,
                              limits: ThemeLimits,
                              assets: ThemeAssetResolver,
                              cache: inout [String: ThemeAssetOutcome],
                              log: inout ThemeIssueLog) -> [String: ThemeValue] {
        var values: [String: ThemeValue] = [:]
        for declaration in declarations {
            guard let token = catalog.descriptor(named: declaration.name) else {
                // Unbekannt heisst meistens: das Theme ist neuer als die App,
                // oder jemand hat sich vertippt. Beides nur ein Hinweis.
                if declaration.name.hasPrefix(ThemeTokenCatalog.prefix) {
                    log.add(.unknownToken(declaration.name), line: declaration.line)
                }
                continue
            }
            guard var value = ThemeValueReader.read(declaration.value, kind: token.kind) else {
                log.add(.unreadableValue(token: token.name, value: shortened(declaration.value)),
                        line: declaration.line)
                continue
            }
            if case let .number(spec) = token.kind, case let .number(raw) = value {
                let clamped = min(max(raw, spec.minimum), spec.maximum)
                if clamped != raw {
                    log.add(.clamped(token: token.name,
                                     value: spec.unit.cssText(raw),
                                     used: spec.unit.cssText(clamped)),
                            line: declaration.line)
                    value = .number(clamped)
                }
            }
            if case .text = token.kind, case let .text(raw) = value, raw.count > limits.maxTextLength {
                log.add(.clamped(token: token.name,
                                 value: "\(raw.count) characters",
                                 used: "\(limits.maxTextLength) characters"),
                        line: declaration.line)
                value = .text(String(raw.prefix(limits.maxTextLength)))
            }
            if case let .file(asset) = value {
                guard !asset.reference.isEmpty else {
                    values[token.name] = .file(.none)
                    continue
                }
                let outcome = cache[asset.reference] ?? assets(asset.reference)
                cache[asset.reference] = outcome
                switch outcome {
                case let .success(url):
                    value = .file(ThemeAsset(reference: asset.reference, url: url))
                case let .failure(reason):
                    log.add(.rejectedAsset(reference: shortened(asset.reference), reason: reason),
                            line: declaration.line)
                    continue
                }
            }
            values[token.name] = value
        }
        return values
    }

    /// Ein Hinweis, der Text aus der Datei zitiert, darf die Anzeige nicht
    /// sprengen.
    private static func shortened(_ text: String) -> String {
        text.count <= 60 ? text : String(text.prefix(60)) + "…"
    }

    private static func withoutDuplicates(_ issues: [ThemeIssue]) -> [ThemeIssue] {
        var seen: Set<ThemeIssue> = []
        return issues.filter { seen.insert($0).inserted }
    }

    private static func cleanIdentifier(_ raw: String) -> String {
        var name = raw.trimmedText
        while name.hasPrefix(".") { name.removeFirst() }
        name = String(name.prefix(120))
        return name.isEmpty ? "theme" : name
    }

    /// Nur ASCII: der Kurzname soll spaeter in einer Adresse und in einem
    /// Dateinamen stehen koennen, ohne dass jemand ueber die Kodierung
    /// nachdenken muss.
    private static func slug(from name: String) -> String {
        var result = ""
        for character in name.lowercased() {
            if character.isASCII, character.isLetter || character.isNumber {
                result.append(character)
            } else if !result.hasSuffix("-") {
                result.append("-")
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        while result.hasPrefix("-") { result.removeFirst() }
        return result.isEmpty ? "theme" : result
    }
}

/// Die Grenzen, die ein Theme nicht ueberschreiten kann.
///
/// Zahlen klemmt schon `Theme.apply` am Bereich des Tokens. Hier steht das,
/// was sich erst aus dem Zusammenspiel ergibt: eine Schriftfarbe, die auf
/// ihrem Untergrund nicht zu lesen waere, wird so weit aufgehellt oder
/// abgedunkelt, bis sie es ist. Ein Theme kann die Shell also nicht blind
/// machen - weder aus Versehen noch mit Absicht.
public enum ThemeGuards {
    static func enforceContrast(in values: inout [String: ThemeValue],
                                catalog: ThemeTokenCatalog,
                                dark: Bool,
                                log: inout ThemeIssueLog) {
        // Ueber den Katalog statt ueber das Woerterbuch: die Reihenfolge der
        // Hinweise soll bei gleicher Datei immer dieselbe sein.
        for token in catalog.tokens {
            // Nennt das Theme den Untergrund nicht, steht die Schrift auf dem
            // der Shell - dem nachempfunden ist die Vorgabe im Verzeichnis.
            guard let rule = token.contrast,
                  let color = values[token.name]?.color,
                  let background = values[rule.background]?.color
                      ?? catalog.descriptor(named: rule.background)?.defaultValue(dark: dark).color
            else { continue }
            let fixed = readable(color, on: background, minimum: rule.minimum)
            guard fixed != color else { continue }
            log.add(.contrastAdjusted(token: token.name, requested: color.cssText,
                                      used: fixed.cssText, dark: dark))
            values[token.name] = .color(fixed)
        }
    }

    /// `color` so weit Richtung Schwarz oder Weiss geschoben, bis der
    /// Kontrast zu `background` reicht. Schon lesbare Farben bleiben genau,
    /// wie sie sind.
    public static func readable(_ color: ThemeColor, on background: ThemeColor, minimum: Double) -> ThemeColor {
        // Die Deckkraft des Untergrunds ist hier ohne Belang: was dahinter
        // liegt, weiss das Theme nicht.
        let base = background.alpha < 1 ? background.withAlpha(1) : background
        func ratio(_ candidate: ThemeColor) -> Double {
            ThemeColor.contrast(candidate.composited(over: base), base)
        }
        guard minimum > 1, ratio(color) < minimum else { return color }
        // Die Richtung, in der ueberhaupt mehr Kontrast zu holen ist. Gleich
        // viel bringen Schwarz und Weiss erst bei einer Helligkeit um 0.18,
        // nicht bei 0.5: auf mittelhellem Grund fuehrt nur Schwarz zum Ziel.
        let target: ThemeColor = ThemeColor.contrast(.black, base) >= ThemeColor.contrast(.white, base)
            ? .black : .white
        var amount = 0.0
        while amount < 1 {
            amount = min(amount + 0.02, 1)
            let candidate = color.blended(with: target, amount: amount)
            if ratio(candidate) >= minimum { return candidate }
        }
        // Selbst reines Schwarz oder Weiss reicht nicht (mittelgrauer
        // Untergrund oder durchsichtige Schrift): dann deckend und in die
        // Richtung, die mehr bringt.
        return ThemeColor.contrast(.white, base) >= ThemeColor.contrast(.black, base) ? .white : .black
    }
}
