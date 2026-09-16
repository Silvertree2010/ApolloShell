import Foundation

/// Obergrenzen beim Lesen eines Themes. Keine davon ist Geschmack: jede
/// verhindert, dass eine Datei den Speicher, die Anzeige oder die Zeit der
/// Shell auffrisst.
public struct ThemeLimits: Equatable, Hashable, Sendable {
    /// Groesste .css-Datei. Darueber wird gar nicht erst gelesen.
    public var maxStyleSheetBytes: Int
    /// Groesstes Bild aus einem Theme-Ordner.
    public var maxAssetBytes: Int
    /// Mehr Zeilen `--x: y;` kann ein Theme nicht haben.
    public var maxDeclarations: Int
    /// Mehr Hinweise werden nicht gesammelt (Zufallsbytes ergeben sonst
    /// beliebig viele).
    public var maxIssues: Int
    /// Laengster Text in einem Token.
    public var maxTextLength: Int
    /// Welche Dateiendungen ein Bild haben darf - klein geschrieben.
    public var imageExtensions: Set<String>

    public init(maxStyleSheetBytes: Int = 512 * 1024,
                maxAssetBytes: Int = 8 * 1024 * 1024,
                maxDeclarations: Int = 4096,
                maxIssues: Int = 200,
                maxTextLength: Int = 200,
                imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif",
                                                "webp", "tiff", "tif", "bmp"]) {
        self.maxStyleSheetBytes = maxStyleSheetBytes
        self.maxAssetBytes = maxAssetBytes
        self.maxDeclarations = maxDeclarations
        self.maxIssues = maxIssues
        self.maxTextLength = maxTextLength
        self.imageExtensions = imageExtensions
    }

    public static let standard = ThemeLimits()
}

/// Entscheidet, ob ein Theme eine Datei benutzen darf, und gibt sie geprueft
/// zurueck.
///
/// Das ist die Sicherheitsgrenze des ganzen Formats: ein Theme aus dem Netz
/// ist fremder Code in Textform, und der einzige Weg nach draussen waere ein
/// Pfad. Deshalb hier und nur hier.
public typealias ThemeAssetOutcome = Result<URL, ThemeAssetRejection>

public struct ThemeAssetResolver: Sendable {
    private let body: @Sendable (String) -> ThemeAssetOutcome

    public init(_ body: @escaping @Sendable (String) -> ThemeAssetOutcome) {
        self.body = body
    }

    public func callAsFunction(_ reference: String) -> ThemeAssetOutcome {
        body(reference)
    }

    /// Ein Theme, das aus einer einzelnen .css-Datei besteht, hat keinen
    /// eigenen Ordner - also auch keine Bilder. Sonst duerfte es im Ordner
    /// aller Themes stoebern.
    public static let none = ThemeAssetResolver { _ in .failure(.needsThemeFolder) }

    /// Dateien aus genau diesem Ordner, sonst nichts.
    ///
    /// Geprueft wird in dieser Reihenfolge, und jede Stufe darf allein
    /// genuegen: Prozentzeichen zuerst aufloesen (sonst schmuggelt `%2e%2e`
    /// ein `..` an der Pruefung vorbei), kein Schema, kein absoluter Pfad,
    /// kein `..`, erlaubte Endung, danach Verknuepfungen aufloesen und den
    /// tatsaechlichen Pfad mit dem Ordner vergleichen. Erst dann wird die
    /// Groesse gemessen.
    public static func folder(_ folder: URL, limits: ThemeLimits = .standard) -> ThemeAssetResolver {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        return ThemeAssetResolver { reference in
            var path = reference.trimmedText
            if path.contains("%") { path = path.removingPercentEncoding ?? path }
            guard !path.isEmpty else { return .failure(.missing) }
            // `:` gibt es in macOS-Dateinamen praktisch nicht, in `http:` und
            // `data:` aber immer.
            guard !path.contains(":") else { return .failure(.notALocalPath) }
            guard !path.hasPrefix("/"), !path.hasPrefix("~"), !path.hasPrefix("\\") else {
                return .failure(.escapesFolder)
            }
            let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !parts.isEmpty, !parts.contains("..") else { return .failure(.escapesFolder) }
            let components = parts.filter { $0 != "." }
            guard let last = components.last else { return .failure(.escapesFolder) }
            let extensionName = (last as NSString).pathExtension.lowercased()
            guard limits.imageExtensions.contains(extensionName) else {
                return .failure(.unsupportedType(extensionName))
            }
            var candidate = root
            for component in components { candidate.appendPathComponent(component) }
            let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
            // Nach dem Aufloesen: liegt die Datei wirklich im Ordner? Eine
            // Verknuepfung nach draussen faellt genau hier durch.
            guard resolved.path.hasPrefix(root.path + "/") else { return .failure(.outsideThemeFolder) }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
                  (attributes[.type] as? FileAttributeType) == .typeRegular else {
                return .failure(.missing)
            }
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard size <= limits.maxAssetBytes else {
                return .failure(.tooLarge(bytes: size, limit: limits.maxAssetBytes))
            }
            return .success(resolved)
        }
    }
}

/// Liest Themes von der Platte. Wirft nie, stuerzt nie ab, gibt immer ein
/// benutzbares Theme zurueck - notfalls die Vorgaben mit einem Hinweis.
///
/// Ein Theme ist entweder
/// - eine einzelne Datei `Name.css` (Kennung: `Name`) oder
/// - ein Ordner `Name/` mit `theme.css` darin (Kennung: `Name`), dann duerfen
///   Bilder daneben liegen.
public enum ThemeLoader {
    /// Die Datei, die ein Theme-Ordner haben muss.
    public static let styleSheetName = "theme.css"
    /// Der Ordner, in dem alle Themes liegen.
    public static let folderName = "themes"

    /// ~/Library/Application Support/ApolloShell/themes
    public static func folder(inApplicationSupport url: URL) -> URL {
        url.appendingPathComponent(folderName, isDirectory: true)
    }

    public static func load(at url: URL,
                            limits: ThemeLimits = .standard,
                            catalog: ThemeTokenCatalog = .standard) -> Theme {
        let manager = FileManager.default
        let identifier = url.pathExtension.lowercased() == "css"
            ? url.deletingPathExtension().lastPathComponent
            : url.lastPathComponent
        func fallback(_ kind: ThemeIssue.Kind) -> Theme {
            Theme.make(identifier: identifier, styleSheet: ThemeStyleSheet(),
                       catalog: catalog, limits: limits, issues: [ThemeIssue(kind)])
        }
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return fallback(.unreadableFile(url.lastPathComponent))
        }
        let sheet = isDirectory.boolValue ? url.appendingPathComponent(styleSheetName) : url
        let assets = isDirectory.boolValue ? ThemeAssetResolver.folder(url, limits: limits) : .none
        guard let attributes = try? manager.attributesOfItem(atPath: sheet.path),
              (attributes[.type] as? FileAttributeType) == .typeRegular else {
            return fallback(.unreadableFile(sheet.lastPathComponent))
        }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= limits.maxStyleSheetBytes else {
            return fallback(.styleSheetTooLarge(bytes: size, limit: limits.maxStyleSheetBytes))
        }
        guard let data = try? Data(contentsOf: sheet) else {
            return fallback(.unreadableFile(sheet.lastPathComponent))
        }
        let (text, issue) = decode(data)
        guard let text else {
            return fallback(issue ?? .notText)
        }
        return Theme.make(identifier: identifier,
                          styleSheet: ThemeStyleSheetParser.parse(text, limits: limits),
                          assets: assets, catalog: catalog, limits: limits,
                          issues: issue.map { [ThemeIssue($0)] } ?? [])
    }

    /// Alle Themes eines Ordners, nach Kennung sortiert. Was kein Theme ist,
    /// wird stumm uebergangen.
    public static func themes(in folder: URL,
                              limits: ThemeLimits = .standard,
                              catalog: ThemeTokenCatalog = .standard) -> [Theme] {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        let sorted = entries.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        var result: [Theme] = []
        for entry in sorted {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                guard manager.fileExists(atPath: entry.appendingPathComponent(styleSheetName).path) else { continue }
            } else {
                guard entry.pathExtension.lowercased() == "css" else { continue }
            }
            result.append(load(at: entry, limits: limits, catalog: catalog))
        }
        return result
    }

    /// Bytes zu Text. Gibt zusaetzlich zurueck, was daran auffiel.
    ///
    /// UTF-8 ist die Vorgabe. Eine Datei mit Byte-Reihenfolge-Marke wird als
    /// UTF-16 gelesen, Nullbytes gelten als "gar kein Text" (jemand hat ein
    /// Bild umbenannt), und was kein gueltiges UTF-8 ist, wird als Latin-1
    /// gelesen: dann stimmen wenigstens die ASCII-Zeilen, und die Farben
    /// kommen an.
    public static func decode(_ data: Data) -> (text: String?, issue: ThemeIssue.Kind?) {
        guard !data.isEmpty else { return ("", nil) }
        let bytes = [UInt8](data.prefix(4))
        let hasUTF16Mark = bytes.count >= 2
            && ((bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF))
        if hasUTF16Mark, let text = String(data: data, encoding: .utf16) {
            return (text, nil)
        }
        var body = data
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            body = data.dropFirst(3)
        }
        if body.prefix(4096).contains(0) { return (nil, .notText) }
        if let text = String(data: body, encoding: .utf8) { return (text, nil) }
        if let text = String(data: body, encoding: .isoLatin1) { return (text, .notUTF8) }
        return (nil, .notText)
    }
}
