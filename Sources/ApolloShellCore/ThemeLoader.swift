import Foundation

public struct ThemeLimits: Equatable, Hashable, Sendable {
    public var maxStyleSheetBytes: Int
    public var maxAssetBytes: Int
    public var maxDeclarations: Int
    public var maxIssues: Int
    public var maxTextLength: Int
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

public typealias ThemeAssetOutcome = Result<URL, ThemeAssetRejection>

public struct ThemeAssetResolver: Sendable {
    private let body: @Sendable (String) -> ThemeAssetOutcome

    public init(_ body: @escaping @Sendable (String) -> ThemeAssetOutcome) {
        self.body = body
    }

    public func callAsFunction(_ reference: String) -> ThemeAssetOutcome {
        body(reference)
    }

    public static let none = ThemeAssetResolver { _ in .failure(.needsThemeFolder) }

    public static func folder(_ folder: URL, limits: ThemeLimits = .standard) -> ThemeAssetResolver {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        return ThemeAssetResolver { reference in
            var path = reference.trimmedText
            if path.contains("%") { path = path.removingPercentEncoding ?? path }
            guard !path.isEmpty else { return .failure(.missing) }
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

public enum ThemeLoader {
    public static let styleSheetName = "theme.css"
    public static let folderName = "themes"

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
        let resolved = sheet.resolvingSymlinksInPath().standardizedFileURL
        if isDirectory.boolValue {
            let root = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(root.path + "/") else {
                return fallback(.unreadableFile(sheet.lastPathComponent))
            }
        }
        guard let attributes = try? manager.attributesOfItem(atPath: resolved.path),
              (attributes[.type] as? FileAttributeType) == .typeRegular else {
            return fallback(.unreadableFile(sheet.lastPathComponent))
        }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= limits.maxStyleSheetBytes else {
            return fallback(.styleSheetTooLarge(bytes: size, limit: limits.maxStyleSheetBytes))
        }
        guard let handle = try? FileHandle(forReadingFrom: resolved),
              let data = try? handle.read(upToCount: limits.maxStyleSheetBytes + 1) ?? Data()
        else {
            return fallback(.unreadableFile(sheet.lastPathComponent))
        }
        try? handle.close()
        guard data.count <= limits.maxStyleSheetBytes else {
            return fallback(.styleSheetTooLarge(bytes: data.count, limit: limits.maxStyleSheetBytes))
        }
        let (text, issue) = decode(data)
        guard let text else {
            return fallback(issue ?? .notText)
        }
        let icons = isDirectory.boolValue ? ThemeIconSet.read(in: url, limits: limits) : (icons: ThemeIconSet.none, issues: [])
        return Theme.make(identifier: identifier,
                          styleSheet: ThemeStyleSheetParser.parse(text, limits: limits),
                          assets: assets, catalog: catalog, limits: limits,
                          issues: (issue.map { [ThemeIssue($0)] } ?? []) + icons.issues,
                          icons: icons.icons)
    }

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
            let isDirectory = (try? entry.resolvingSymlinksInPath()
                .resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                guard manager.fileExists(atPath: entry.appendingPathComponent(styleSheetName).path) else { continue }
            } else {
                guard entry.pathExtension.lowercased() == "css" else { continue }
            }
            result.append(load(at: entry, limits: limits, catalog: catalog))
        }
        return result
    }

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
