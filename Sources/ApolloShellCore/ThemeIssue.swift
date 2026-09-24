import Foundation

/// Was beim Lesen eines Themes aufgefallen ist.
///
/// Ein Hinweis ist nie ein Fehler: das Theme laedt immer, notfalls mit
/// Vorgaben. Die Hinweise sind fuer den, der das Theme schreibt - Nexus zeigt
/// sie spaeter an.
///
/// Absichtlich nur Daten, kein fertiger Satz: die Oberflaeche uebersetzt
/// selbst (UI-Text steht in dieser Anwendung auf Deutsch im Code und geht
/// durch Support/Localization). `description` ist englisch und fuer Protokolle
/// und Tests gedacht, nicht fuer das Fenster.
public struct ThemeIssue: Equatable, Hashable, Sendable, CustomStringConvertible {
    public enum Kind: Equatable, Hashable, Sendable {
        /// `--apollo-…`, aber kein Token, das diese Fassung kennt. Ein Theme
        /// aus einer spaeteren Fassung sieht genau so aus - deshalb nur ein
        /// Hinweis.
        case unknownToken(String)
        /// Eine Datei in `icons/`, deren Name keine Symbol-Kennung dieser
        /// Fassung ist. Wie bei einem unbekannten Token nur ein Hinweis.
        case unknownIcon(String)
        /// Der Wert passt nicht zum Typ des Tokens. Es gilt die Vorgabe (oder
        /// der letzte lesbare Wert desselben Tokens).
        case unreadableValue(token: String, value: String)
        /// Der Wert lag ausserhalb des erlaubten Bereichs und wurde geklemmt.
        case clamped(token: String, value: String, used: String)
        /// Die Schriftfarbe war auf ihrem Untergrund nicht zu lesen und wurde
        /// aufgehellt oder abgedunkelt. `dark` sagt, in welchem
        /// Erscheinungsbild - eine helle Schriftfarbe ohne dunkle Abweichung
        /// faellt nur dort auf.
        case contrastAdjusted(token: String, requested: String, used: String, dark: Bool)
        /// Eine Zeile, die nicht zur unterstuetzten CSS-Teilmenge gehoert.
        case ignoredRule(String)
        /// Datei, die nicht benutzt werden darf (Pfad zeigt hinaus, zu gross,
        /// fehlt, falsche Art).
        case rejectedAsset(reference: String, reason: ThemeAssetRejection)
        /// Das Theme nennt eine hoehere Formatnummer, als diese Fassung kennt.
        case newerFormat(found: Int, known: Int)
        /// Die Datei ist groesser als erlaubt und wurde gar nicht gelesen.
        case styleSheetTooLarge(bytes: Int, limit: Int)
        /// Kein Text (Nullbytes) - vermutlich versehentlich eine Bilddatei.
        case notText
        /// Kein gueltiges UTF-8; als Latin-1 gelesen, damit wenigstens die
        /// ASCII-Zeilen ankommen.
        case notUTF8
        /// Datei oder Ordner liess sich nicht lesen.
        case unreadableFile(String)
        /// Mehr Zeilen, als eine Formatvorlage haben darf; der Rest wurde
        /// uebersprungen.
        case tooManyDeclarations(limit: Int)
        /// Es gab noch mehr Hinweise; gesammelt wird nur bis zur Obergrenze.
        case moreIssues(dropped: Int)
    }

    public let kind: Kind
    /// Zeile in der CSS-Datei, 1-basiert. `nil`, wenn es keine Zeile gibt
    /// (Datei zu gross, Ordner unlesbar).
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

/// Warum eine Datei aus einem Theme nicht benutzt wird. Die ersten vier
/// Gruende sind Sicherheit: ein Theme darf nur aus dem eigenen Ordner lesen.
public enum ThemeAssetRejection: Error, Equatable, Hashable, Sendable, CustomStringConvertible {
    /// `..`, ein absoluter Pfad oder `~` - zeigt aus dem Ordner hinaus.
    case escapesFolder
    /// `http:`, `file:`, `data:` und alles andere mit Schema.
    case notALocalPath
    /// Nach dem Aufloesen von Verknuepfungen liegt die Datei ausserhalb.
    case outsideThemeFolder
    /// Ein einzelnes .css-Theme hat keinen eigenen Ordner und damit keine
    /// Dateien - wer Bilder will, macht einen Ordner mit theme.css.
    case needsThemeFolder
    /// Gibt es nicht oder ist keine gewoehnliche Datei.
    case missing
    /// Groesser als erlaubt.
    case tooLarge(bytes: Int, limit: Int)
    /// Keine der erlaubten Bildendungen.
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

/// Sammelt Hinweise und hoert bei einer Obergrenze auf - eine Datei aus
/// Zufallsbytes soll nicht Tausende Hinweise in den Speicher schreiben.
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

    /// Am Ende: die gesammelten Hinweise, notfalls mit dem Vermerk, wie viele
    /// fehlen.
    func finished() -> [ThemeIssue] {
        dropped == 0 ? issues : issues + [ThemeIssue(.moreIssues(dropped: dropped))]
    }
}
