import AppKit
import ApolloConfig

@MainActor
protocol AppIconSource: AnyObject {
    func icon(for app: Value) -> NSImage?
}

enum AppIconKey {
    static func bundleID(_ app: Value) -> String? {
        switch app {
        case .string(let id): id
        case .record(let record):
            if case .string(let id)? = record["bundle-id"] { id } else { nil }
        case .image(let ref) where ref.source == "app-icon": ref.id
        default: nil
        }
    }
}

@MainActor
final class WorkspaceAppIcons: AppIconSource {
    private var cache: [String: NSImage] = [:]

    func icon(for app: Value) -> NSImage? {
        guard let id = AppIconKey.bundleID(app) else { return nil }
        if let cached = cache[id] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[id] = image
        return image
    }
}

@MainActor
final class FixtureAppIcons: AppIconSource {
    static let colors: [String: NSColor] = [
        "com.apple.finder": .systemBlue,
        "com.apple.Safari": .systemTeal,
        "com.apple.mail": .systemIndigo,
    ]

    let files: [String: String]
    let root: URL?
    private var cache: [String: NSImage] = [:]

    init(files: [String: String] = [:], root: URL? = nil) {
        self.files = files
        self.root = root
    }

    func icon(for app: Value) -> NSImage? {
        guard let id = AppIconKey.bundleID(app) else { return nil }
        if let cached = cache[id] { return cached }
        let image = file(id) ?? Self.swatch(Self.colors[id] ?? .systemGray)
        cache[id] = image
        return image
    }

    private func file(_ id: String) -> NSImage? {
        guard let root, let path = files[id] else { return nil }
        return SafeImageFile.image(path, root: root)
    }

    static func swatch(_ color: NSColor) -> NSImage {
        let side: CGFloat = 64
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: side * 0.22, yRadius: side * 0.22).fill()
            return true
        }
    }
}

enum FixtureIcons {
    static func extract(_ values: [String: Record]) -> (values: [String: Record], icons: [String: String]) {
        var icons: [String: String] = [:]
        func strip(_ value: Value) -> Value {
            switch value {
            case .record(let record):
                if case .string(let id)? = record["bundle-id"], case .string(let path)? = record["icon"] {
                    icons[id] = path
                }
                let keep = record.keys.filter { $0 != "icon" || record["bundle-id"] == nil }
                return .record(Record(keep.map { ($0, strip(record[$0] ?? .null)) }))
            case .list(let items):
                return .list(items.map(strip))
            default:
                return value
            }
        }
        var result: [String: Record] = [:]
        for (name, record) in values {
            if case .record(let stripped) = strip(.record(record)) { result[name] = stripped }
        }
        return (result, icons)
    }
}
