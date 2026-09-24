import Foundation

public struct UtilitiesShortcutOptions: Codable, Equatable, Sendable {
    public static let fallbackSymbol = "square.2.layers.3d.fill"

    public var name: String
    public var identifier: String
    public var title: String
    public var symbol: String

    public init(name: String = "", identifier: String = "", title: String = "", symbol: String = "") {
        self.name = name
        self.identifier = identifier
        self.title = title
        self.symbol = symbol
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.name, into: &name)
        c.lenient(.identifier, into: &identifier)
        c.lenient(.title, into: &title)
        c.lenient(.symbol, into: &symbol)
    }
}

// MARK: - Links

public enum UtilitiesLink {
    /// Aus dem Eingabefeld eine Adresse:
    /// - mit Schema (https:, mailto:, x-apple.systempreferences: ...) wie
    ///   eingegeben; http(s) braucht einen Host.
    /// - ohne Schema, aber mit Punkt oder "localhost" ("example.com",
    ///   "localhost:8080"): https:// davor - so tippt man Adressen.
    /// - leer, mit Leerzeichen oder sonst nichts Erkennbares: `nil`.
    public static func url(from input: String) -> URL? {
        let text = input.trimmed
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        if let scheme = scheme(of: text) {
            guard let url = URL(string: text), url.scheme?.lowercased() == scheme else { return nil }
            if scheme == "http" || scheme == "https" {
                guard let host = url.host(), !host.isEmpty else { return nil }
            }
            return url
        }
        guard text.contains(".") || text.lowercased().hasPrefix("localhost"),
              let url = URL(string: "https://" + text), let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    /// Kurz fuer Tooltips: ohne Schema, ohne "www." und ohne Schraegstrich
    /// am Ende ("example.com/docs"). Andere Schemata ganz.
    public static func displayText(_ url: URL) -> String {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host()
        else { return url.absoluteString }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = url.path()
        return path.isEmpty || path == "/" ? host : host + (path.hasSuffix("/") ? String(path.dropLast()) : path)
    }

    /// Schema nach RFC 3986 (Buchstabe, dann Buchstaben, Ziffern, + . -) vor
    /// dem ersten Doppelpunkt - ausser danach kommen nur Ziffern: das ist
    /// "host:port" ohne Schema.
    private static func scheme(of text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let head = text[..<colon]
        guard let first = head.first, first.isASCII, first.isLetter,
              head.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+.-".contains($0)) })
        else { return nil }
        let tail = text[text.index(after: colon)...].prefix { $0 != "/" }
        if !tail.isEmpty, tail.allSatisfy(\.isNumber) { return nil }
        return head.lowercased()
    }
}

// MARK: - Kurzbefehle

/// Ein Eintrag aus `shortcuts list --show-identifiers`.
public struct UtilitiesShortcut: Equatable, Sendable, Identifiable {
    public var name: String
    public var identifier: String

    public var id: String { identifier.isEmpty ? name : identifier }

    public init(name: String, identifier: String) {
        self.name = name
        self.identifier = identifier
    }
}

/// Apples Kurzbefehle ueber das mitgelieferte Werkzeug /usr/bin/shortcuts:
/// oeffentlich, ohne Freigabe-Dialog, und der einzige Weg, z. B. einen
/// Fokus ("Nicht stoeren") zu schalten, ohne private Schnittstellen.
public enum UtilitiesShortcuts {
    public static let tool = "/usr/bin/shortcuts"
    public static let listArguments = ["list", "--show-identifiers"]

    /// Jede Zeile "Name (KENNUNG)" - die Kennung ist eine UUID in Klammern
    /// am Zeilenende (gemessen 14.09., macOS 26.6). Namen duerfen selbst
    /// Klammern enthalten, deshalb von hinten. Zeilen ohne Kennung: nur der
    /// Name. Sortiert nach Namen wie in der Kurzbefehle-App.
    public static func parse(_ output: String) -> [UtilitiesShortcut] {
        output.split(whereSeparator: \.isNewline).compactMap { raw -> UtilitiesShortcut? in
            let line = String(raw).trimmed
            guard !line.isEmpty else { return nil }
            if line.hasSuffix(")"), let open = line.lastIndex(of: "(") {
                let candidate = String(line[line.index(after: open)..<line.index(before: line.endIndex)])
                if UUID(uuidString: candidate) != nil {
                    // Nur eine Kennung ohne Namen: nichts, was man waehlen koennte.
                    let name = String(line[..<open]).trimmed
                    return name.isEmpty ? nil : UtilitiesShortcut(name: name, identifier: candidate)
                }
            }
            return UtilitiesShortcut(name: line, identifier: "")
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Argumente fuer `shortcuts run`: lieber die Kennung (ueberlebt
    /// Umbenennen), sonst der Name. `nil`: nichts gewaehlt.
    public static func runArguments(_ options: UtilitiesShortcutOptions) -> [String]? {
        if let id = options.identifier.trimmed.nonEmpty { return ["run", id] }
        if let name = options.name.trimmed.nonEmpty { return ["run", name] }
        return nil
    }
}

extension ToastText {
    /// `shortcuts run` endete mit Fehler (Kurzbefehl geloescht, abgebrochen).
    public static func shortcutFailed(_ name: String) -> Content {
        Content(title: String(localized: "Shortcut Failed"),
                message: name.trimmed.nonEmpty ?? String(localized: "Unknown Shortcut"),
                symbol: UtilitiesShortcutOptions.fallbackSymbol, kind: .warning)
    }
}

// MARK: - Apps ausblenden

public enum UtilitiesHideApps {
    /// Welche App ausgeblendet wird: nur normale Apps (mit Dock-Symbol),
    /// nie die Shell selbst - sonst verschwaenden Leiste und Panels -, und
    /// bei `keepFrontmost` nicht die vordere.
    public static func shouldHide(pid: Int32, isRegular: Bool, ownPID: Int32, frontmostPID: Int32?,
                                  keepFrontmost: Bool) -> Bool {
        guard isRegular, pid != ownPID else { return false }
        return !(keepFrontmost && pid == frontmostPID)
    }
}

// MARK: - Symbole

/// Die kleine Auswahl in Nexus fuer eigene Knoepfe. Jedes davon gibt es auf
/// macOS 26 (Bildprobe prueft es); ein eigener Name geht zusaetzlich.
public enum UtilitiesSymbols {
    public static let choices: [String] = [
        "app.fill", "link", "globe", "square.2.layers.3d.fill", "star.fill", "heart.fill", "bolt.fill",
        "moon.fill", "sun.max.fill", "bell.fill", "bell.slash.fill", "music.note", "play.fill", "headphones",
        "house.fill", "envelope.fill", "message.fill", "calendar", "note.text", "checklist", "book.fill",
        "doc.fill", "folder.fill", "terminal.fill", "hammer.fill", "paintbrush.fill", "camera.fill", "photo.fill",
        "film.fill", "gamecontroller.fill", "cup.and.saucer.fill", "lightbulb.fill", "timer", "alarm.fill",
        "flag.fill", "bookmark.fill", "cart.fill", "briefcase.fill", "chart.bar.fill", "keyboard.fill",
        "printer.fill", "network", "server.rack", "key.fill", "sparkles", "wand.and.stars", "leaf.fill", "airplane",
    ]
}

// MARK: - Hilfen

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
