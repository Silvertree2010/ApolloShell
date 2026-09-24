import Foundation

public enum MarketInstallProblem: Error, Equatable, Sendable, CustomStringConvertible {
    case badID
    case badSlug(String)
    case badVersion(Int)
    case tooLarge(bytes: Int, limit: Int)
    case notText
    case usesFiles
    case noTokens
    case foreignRule(String)
    case occupied(String)
    case notInstalled

    public var description: String {
        switch self {
        case .badID: "The Marketplace sent a theme without a usable id."
        case .badSlug(let slug): "The Marketplace sent a theme with the unusable name \"\(slug)\"."
        case .badVersion(let version): "The Marketplace sent a theme with the unusable version \(version)."
        case .tooLarge(let bytes, let limit): "The theme is too large (\(bytes) bytes, at most \(limit))."
        case .notText: "The theme is not plain text."
        case .usesFiles: "This theme uses images. The Marketplace takes plain CSS themes only for now."
        case .noTokens: "There is nothing in this theme the shell knows."
        case .foreignRule(let rule): "The theme contains \(rule), which a Marketplace theme may not use."
        case .occupied(let name): "\(name) is in the way and is not a theme file."
        case .notInstalled: "This theme is not installed."
        }
    }
}

public struct MarketThemeInstaller: Sendable {
    public enum State: String, Sendable {
        case get, update, use
    }

    public static let maxCSSBytes = 64 * 1024
    public static let maxSlugLength = 80
    public static let maxIDLength = 128
    public static let fileMode: Int16 = 0o644
    public static let folderMode: Int16 = 0o755

    public let themes: URL
    public let legacyThemes: URL
    public let indexFile: URL

    public init(themes: URL, legacyThemes: URL, indexFile: URL) {
        self.themes = themes
        self.legacyThemes = legacyThemes
        self.indexFile = indexFile
    }

    public func index() -> MarketInstallIndex {
        MarketInstallIndex.load(from: indexFile)
    }

    public static func check(_ theme: MarketTheme) throws(MarketInstallProblem) {
        guard !theme.id.isEmpty, theme.id.count <= maxIDLength,
              theme.id.unicodeScalars.allSatisfy({ isASCIIAlphanumeric($0) || $0 == "-" || $0 == "_" })
        else { throw .badID }
        guard isSlug(theme.slug) else { throw .badSlug(theme.slug) }
        guard theme.version >= 1 else { throw .badVersion(theme.version) }
        try checkCSS(theme.css, identifier: theme.slug)
    }

    public static func checkCSS(_ css: String, identifier: String) throws(MarketInstallProblem) {
        let bytes = css.utf8.count
        guard bytes <= maxCSSBytes else { throw .tooLarge(bytes: bytes, limit: maxCSSBytes) }
        guard !css.unicodeScalars.contains(where: { $0 == "\0" }) else { throw .notText }
        let rules = withoutStringsAndComments(css).lowercased()
        if rules.contains("url(") || rules.contains("image-set(") { throw .usesFiles }
        for rule in ["@import", "@font-face", "@namespace", "expression("] where rules.contains(rule) {
            throw .foreignRule(rule)
        }
        let parsed = Theme.make(identifier: identifier, styleSheet: ThemeStyleSheetParser.parse(css))
        switch ThemeCanonical.css(for: parsed) {
        case .success: return
        case .failure(.usesFiles): throw .usesFiles
        case .failure(.noTokens): throw .noTokens
        }
    }

    static func withoutStringsAndComments(_ css: String) -> String {
        var out = String.UnicodeScalarView()
        var quote: Unicode.Scalar?
        var inComment = false
        var escaped = false
        var previous: Unicode.Scalar?
        for scalar in css.unicodeScalars {
            if inComment {
                if previous == "*" && scalar == "/" { inComment = false; previous = nil } else { previous = scalar }
                out.append(" ")
                continue
            }
            if let open = quote {
                if escaped { escaped = false } else if scalar == "\\" { escaped = true } else if scalar == open || scalar == "\n" { quote = nil }
                out.append(" ")
                continue
            }
            if scalar == "\"" || scalar == "'" {
                quote = scalar
                out.append(" ")
            } else if scalar == "*" && previous == "/" {
                inComment = true
                previous = nil
                out.append(" ")
                continue
            } else {
                out.append(scalar)
            }
            previous = scalar
        }
        return String(out)
    }

    public static func isSlug(_ slug: String) -> Bool {
        guard !slug.isEmpty, slug.count <= maxSlugLength, !slug.hasPrefix("-"), !slug.hasSuffix("-"), !slug.contains("--")
        else { return false }
        return slug.unicodeScalars.allSatisfy { ($0.value >= 0x61 && $0.value <= 0x7A) || ($0.value >= 0x30 && $0.value <= 0x39) || $0 == "-" }
    }

    static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value >= 0x30 && scalar.value <= 0x39) || (scalar.value >= 0x41 && scalar.value <= 0x5A) || (scalar.value >= 0x61 && scalar.value <= 0x7A)
    }

    static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 255 && !name.hasPrefix(".") && !name.contains("/") && !name.contains("\0")
            && name.lowercased().hasSuffix(".css") && name.count > 4
    }

    public static func identifier(fileName: String) -> String {
        String(fileName.dropLast(4))
    }

    func entry(_ id: String, in index: MarketInstallIndex) -> MarketInstallIndex.Entry? {
        guard let entry = index.entries[id], Self.isPlainFileName(entry.fileName) else { return nil }
        return entry
    }

    func installedFile(_ entry: MarketInstallIndex.Entry) -> URL? {
        [themes, legacyThemes]
            .map { $0.appendingPathComponent(entry.fileName) }
            .first { Self.isRegularFile($0) }
    }

    public func state(of theme: MarketTheme, index: MarketInstallIndex? = nil) -> State {
        let index = index ?? self.index()
        guard let entry = entry(theme.id, in: index), installedFile(entry) != nil else { return .get }
        return entry.version < theme.version ? .update : .use
    }

    public func installedIdentifier(of id: String, index: MarketInstallIndex? = nil) -> String? {
        let index = index ?? self.index()
        guard let entry = entry(id, in: index), installedFile(entry) != nil else { return nil }
        return Self.identifier(fileName: entry.fileName)
    }

    @discardableResult
    public func install(_ theme: MarketTheme) throws -> String {
        try Self.check(theme)
        let manager = FileManager.default
        try manager.createDirectory(at: themes, withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: Self.folderMode)])
        var index = self.index()
        let fileName = entry(theme.id, in: index)?.fileName ?? freeFileName(for: theme.slug)
        let target = themes.appendingPathComponent(fileName)
        if let type = Self.fileType(target) {
            switch type {
            case .typeSymbolicLink: try manager.removeItem(at: target)
            case .typeRegular: break
            default: throw MarketInstallProblem.occupied(fileName)
            }
        }
        let data = Data(MarketInstall.fileContents(for: theme).utf8)
        try data.write(to: target, options: .atomic)
        try manager.setAttributes([.posixPermissions: NSNumber(value: Self.fileMode)], ofItemAtPath: target.path)
        index.entries[theme.id] = .init(fileName: fileName, version: theme.version)
        try manager.createDirectory(at: indexFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try index.save(to: indexFile)
        return Self.identifier(fileName: fileName)
    }

    @discardableResult
    public func remove(_ id: String) throws -> String {
        var index = self.index()
        guard let entry = entry(id, in: index) else { throw MarketInstallProblem.notInstalled }
        let manager = FileManager.default
        for folder in [themes, legacyThemes] {
            let file = folder.appendingPathComponent(entry.fileName)
            if let type = Self.fileType(file), type == .typeRegular || type == .typeSymbolicLink {
                try manager.removeItem(at: file)
            }
        }
        index.entries[id] = nil
        try index.save(to: indexFile)
        return Self.identifier(fileName: entry.fileName)
    }

    func freeFileName(for slug: String) -> String {
        let taken = Set(index().entries.values.map { $0.fileName.lowercased() })
        var counter = 1
        while true {
            let base = counter == 1 ? slug : "\(slug)-\(counter)"
            let name = base + ".css"
            let used = taken.contains(name.lowercased())
                || [themes, legacyThemes].contains { folder in
                    Self.fileType(folder.appendingPathComponent(name)) != nil || Self.fileType(folder.appendingPathComponent(base)) != nil
                }
            if !used { return name }
            counter += 1
        }
    }

    static func fileType(_ url: URL) -> FileAttributeType? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.type] as? FileAttributeType
    }

    static func isRegularFile(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        return fileType(resolved) == .typeRegular
    }
}
