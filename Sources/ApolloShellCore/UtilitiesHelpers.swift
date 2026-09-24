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

public enum UtilitiesLink {
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

    public static func displayText(_ url: URL) -> String {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host()
        else { return url.absoluteString }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = url.path()
        return path.isEmpty || path == "/" ? host : host + (path.hasSuffix("/") ? String(path.dropLast()) : path)
    }

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

public struct UtilitiesShortcut: Equatable, Sendable, Identifiable {
    public var name: String
    public var identifier: String

    public var id: String { identifier.isEmpty ? name : identifier }

    public init(name: String, identifier: String) {
        self.name = name
        self.identifier = identifier
    }
}

public enum UtilitiesShortcuts {
    public static let tool = "/usr/bin/shortcuts"
    public static let listArguments = ["list", "--show-identifiers"]

    public static func parse(_ output: String) -> [UtilitiesShortcut] {
        output.split(whereSeparator: \.isNewline).compactMap { raw -> UtilitiesShortcut? in
            let line = String(raw).trimmed
            guard !line.isEmpty else { return nil }
            if line.hasSuffix(")"), let open = line.lastIndex(of: "(") {
                let candidate = String(line[line.index(after: open)..<line.index(before: line.endIndex)])
                if UUID(uuidString: candidate) != nil {
                    let name = String(line[..<open]).trimmed
                    return name.isEmpty ? nil : UtilitiesShortcut(name: name, identifier: candidate)
                }
            }
            return UtilitiesShortcut(name: line, identifier: "")
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func runArguments(_ options: UtilitiesShortcutOptions) -> [String]? {
        if let id = options.identifier.trimmed.nonEmpty { return ["run", id] }
        if let name = options.name.trimmed.nonEmpty { return ["run", name] }
        return nil
    }
}

extension ToastText {
    public static func shortcutFailed(_ name: String) -> Content {
        Content(title: String(localized: "Shortcut Failed"),
                message: name.trimmed.nonEmpty ?? String(localized: "Unknown Shortcut"),
                symbol: UtilitiesShortcutOptions.fallbackSymbol, kind: .warning)
    }
}

public enum UtilitiesHideApps {
    public static func shouldHide(pid: Int32, isRegular: Bool, ownPID: Int32, frontmostPID: Int32?,
                                  keepFrontmost: Bool) -> Bool {
        guard isRegular, pid != ownPID else { return false }
        return !(keepFrontmost && pid == frontmostPID)
    }
}

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

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
