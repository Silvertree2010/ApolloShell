import CoreGraphics
import Foundation

public struct StatusItemRecord: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String?
    public var index: Int
    public var frame: CGRect
    public var title: String
    public var label: String

    public init(pid: Int32, bundleID: String?, index: Int, frame: CGRect, title: String = "", label: String = "") {
        self.pid = pid
        self.bundleID = bundleID
        self.index = index
        self.frame = frame
        self.title = title
        self.label = label
    }

    public var id: String { "\(pid)-\(index)" }

    public var name: String { title.isEmpty ? label : title }
}

public enum StatusItemOrder {
    public static func isSystem(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleID.hasPrefix("com.apple.")
    }

    public static func mirrored(_ records: [StatusItemRecord]) -> [StatusItemRecord] {
        records
            .filter { !isSystem(bundleID: $0.bundleID) && $0.frame.width > 0 && $0.frame.height > 0 }
            .sorted { a, b in
                if a.frame.minX != b.frame.minX { return a.frame.minX < b.frame.minX }
                if a.pid != b.pid { return a.pid < b.pid }
                return a.index < b.index
            }
    }

    public static func window(for item: CGRect, among windows: [CGRect], tolerance: CGFloat = 6) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, window) in windows.enumerated() {
            let distance = abs(window.midX - item.midX)
            guard distance <= tolerance, window.minX < item.maxX, window.maxX > item.minX else { continue }
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best?.index
    }
}

public enum StatusItemTint {
    public static func isMonochrome(rgba: [UInt8], spread: Int = 24, minimumAlpha: UInt8 = 40) -> Bool {
        var index = 0
        var coloured = 0
        var visible = 0
        while index + 3 < rgba.count {
            let alpha = rgba[index + 3]
            if alpha >= minimumAlpha {
                visible += 1
                let r = Int(rgba[index]), g = Int(rgba[index + 1]), b = Int(rgba[index + 2])
                if max(r, g, b) - min(r, g, b) > spread { coloured += 1 }
            }
            index += 4
        }
        return coloured <= max(visible / 50, 1)
    }
}
