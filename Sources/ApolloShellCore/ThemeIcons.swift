import Foundation

public struct ThemeIconDescriptor: Equatable, Hashable, Sendable {
    public let id: String
    public let fallback: String
    public let summary: String
    public let aliases: [String]

    public init(id: String, fallback: String, summary: String, aliases: [String] = []) {
        self.id = id
        self.fallback = fallback
        self.summary = summary
        self.aliases = aliases
    }
}

public struct ThemeIconCatalog: Sendable {
    public let icons: [ThemeIconDescriptor]
    private let index: [String: Int]

    public init(_ icons: [ThemeIconDescriptor]) {
        self.icons = icons
        var index: [String: Int] = [:]
        for (position, icon) in icons.enumerated() {
            for key in ([icon.id] + icon.aliases).map({ $0.lowercased() }) where index[key] == nil {
                index[key] = position
            }
        }
        self.index = index
    }

    public func descriptor(for id: String) -> ThemeIconDescriptor? {
        index[id.lowercased()].map { icons[$0] }
    }

    public func contains(_ id: String) -> Bool { descriptor(for: id) != nil }

    public static let folderName = "icons"

    public static let standard = ThemeIconCatalog(ThemeIconCatalog.standardIcons)

    static let standardIcons: [ThemeIconDescriptor] = [
        .init(id: "bar-dashboard", fallback: "square.grid.2x2.fill", summary: "Opens the dashboard"),
        .init(id: "bar-utilities", fallback: "slider.horizontal.3", summary: "Opens the control centre"),
        .init(id: "bar-clock", fallback: "calendar", summary: "Above the clock in the bar"),
        .init(id: "bar-power", fallback: "power", summary: "Opens the session menu"),
        .init(id: "bar-launcher", fallback: "magnifyingglass", summary: "Opens the launcher"),

        .init(id: "status-wifi", fallback: "wifi", summary: "Wi-Fi, when it is connected"),
        .init(id: "status-wifi-off", fallback: "wifi.slash", summary: "Wi-Fi, when it is off"),
        .init(id: "status-bluetooth", fallback: "bluetooth", summary: "Bluetooth, when it is on"),
        .init(id: "status-bluetooth-off", fallback: "bluetooth.slash", summary: "Bluetooth, when it is off"),
        .init(id: "status-battery", fallback: "battery.100percent", summary: "Battery"),
        .init(id: "status-battery-charging", fallback: "battery.100percent.bolt", summary: "Battery while charging"),
        .init(id: "status-volume", fallback: "speaker.wave.2.fill", summary: "Volume"),
        .init(id: "status-volume-muted", fallback: "speaker.slash.fill", summary: "Volume, when it is muted"),

        .init(id: "session-emblem", fallback: "", summary: "The emblem in the middle of the session menu"),
        .init(id: "session-logout", fallback: "rectangle.portrait.and.arrow.right", summary: "Log out"),
        .init(id: "session-sleep", fallback: "moon.fill", summary: "Sleep"),
        .init(id: "session-restart", fallback: "arrow.clockwise", summary: "Restart"),
        .init(id: "session-shutdown", fallback: "power", summary: "Shut down"),

        .init(id: "toast-info", fallback: "info.circle.fill", summary: "A toast that just says something"),
        .init(id: "toast-success", fallback: "checkmark.circle.fill", summary: "A toast about something that worked"),
        .init(id: "toast-warning", fallback: "exclamationmark.triangle.fill", summary: "A toast that warns"),
        .init(id: "toast-error", fallback: "exclamationmark.circle.fill", summary: "A toast about a failure"),

        .init(id: "panel-media", fallback: "music.note", summary: "Media, and the placeholder without artwork"),
        .init(id: "panel-performance", fallback: "speedometer", summary: "The performance tab"),
        .init(id: "panel-weather", fallback: "cloud.sun.fill", summary: "The weather tab"),
        .init(id: "panel-cpu", fallback: "cpu", summary: "Processor load"),
        .init(id: "panel-memory", fallback: "memorychip", summary: "Memory in use"),
        .init(id: "panel-disk", fallback: "internaldrive", summary: "Disk in use"),
    ]
}

public struct ThemeIconSet: Equatable, Sendable {
    public let files: [String: URL]

    public init(files: [String: URL] = [:]) {
        self.files = files
    }

    public static let none = ThemeIconSet()

    public var isEmpty: Bool { files.isEmpty }

    public func file(_ id: String, catalog: ThemeIconCatalog = .standard) -> URL? {
        if let url = files[id.lowercased()] { return url }
        guard let descriptor = catalog.descriptor(for: id) else { return nil }
        for key in [descriptor.id] + descriptor.aliases {
            if let url = files[key.lowercased()] { return url }
        }
        return nil
    }

    public static func read(in folder: URL,
                            limits: ThemeLimits = .standard,
                            catalog: ThemeIconCatalog = .standard) -> (icons: ThemeIconSet, issues: [ThemeIssue]) {
        let iconsFolder = folder.appendingPathComponent(ThemeIconCatalog.folderName, isDirectory: true)
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: iconsFolder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return (.none, [])
        }
        guard let entries = try? manager.contentsOfDirectory(
            at: iconsFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return (.none, []) }

        let resolver = ThemeAssetResolver.folder(folder, limits: limits)
        var files: [String: URL] = [:]
        var issues: [ThemeIssue] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let id = entry.deletingPathExtension().lastPathComponent.lowercased()
            guard catalog.contains(id) else {
                issues.append(ThemeIssue(.unknownIcon(entry.lastPathComponent)))
                continue
            }
            let reference = "\(ThemeIconCatalog.folderName)/\(entry.lastPathComponent)"
            switch resolver(reference) {
            case let .success(url):
                if files[id] == nil { files[id] = url }
            case let .failure(reason):
                issues.append(ThemeIssue(.rejectedAsset(reference: reference, reason: reason)))
            }
        }
        return (ThemeIconSet(files: files), issues)
    }
}
