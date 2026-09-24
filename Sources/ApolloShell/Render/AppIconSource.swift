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

    private var cache: [String: NSImage] = [:]

    func icon(for app: Value) -> NSImage? {
        guard let id = AppIconKey.bundleID(app) else { return nil }
        if let cached = cache[id] { return cached }
        let color = Self.colors[id] ?? .systemGray
        let side: CGFloat = 64
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: side * 0.22, yRadius: side * 0.22).fill()
            return true
        }
        cache[id] = image
        return image
    }
}
