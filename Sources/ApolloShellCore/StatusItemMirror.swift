import CoreGraphics
import Foundation

// The status items of other apps (Docker, Spotify ...) mirrored into the
// menu bar (spec topbar.md, "Menüs fremder Statussymbole"). The app layer
// reads them through accessibility (`AXExtrasMenuBar` of every app) and
// their images through ScreenCaptureKit; which ones stand where and which
// window belongs to which item is decided here.

/// One status item as accessibility reports it.
public struct StatusItemRecord: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String?
    /// Its place in the app's `AXExtrasMenuBar` - with the pid its identity.
    public var index: Int
    /// In accessibility coordinates: top left of the main screen, y down.
    public var frame: CGRect
    /// Text items ("PMenu") have a title; icons mostly only a description.
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

    /// What a tooltip and VoiceOver say.
    public var name: String { title.isEmpty ? label : title }
}

public enum StatusItemOrder {
    /// Apple's own status items: clock, Control Centre, Wi-Fi, Spotlight,
    /// the input source. The shell draws its own modules for those.
    public static func isSystem(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleID.hasPrefix("com.apple.")
    }

    /// The items to mirror, in the order Apple's menu bar shows them: left
    /// to right. Apple's own ones and empty frames (a switched-off item
    /// reports 0 x 0, measured on Control Centre) fall away; equal x keeps
    /// the app's own order.
    public static func mirrored(_ records: [StatusItemRecord]) -> [StatusItemRecord] {
        records
            .filter { !isSystem(bundleID: $0.bundleID) && $0.frame.width > 0 && $0.frame.height > 0 }
            .sorted { a, b in
                if a.frame.minX != b.frame.minX { return a.frame.minX < b.frame.minX }
                if a.pid != b.pid { return a.pid < b.pid }
                return a.index < b.index
            }
    }

    /// The window that draws an item. Since macOS 26 every status item
    /// window belongs to Control Centre ("Item-0"), not to the app, so only
    /// the position ties them together: accessibility reports the item a
    /// little narrower than its window (792/34 against 793/32, measured),
    /// hence the centres, within `tolerance`. `nil` when none is close.
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

/// Whether a captured status item image is a monochrome glyph (drawn in
/// the menu bar's text colour, so it can take ours) or has colours of its
/// own that should stay.
public enum StatusItemTint {
    /// - Parameter rgba: 8-bit RGBA, premultiplied or not.
    /// - Returns: true when every visible pixel is grey (its channels at
    ///   most `spread` apart). An empty image counts as monochrome.
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
        // A few coloured pixels are antialiasing against a coloured wallpaper
        // edge, not a colour of the icon.
        return coloured <= max(visible / 50, 1)
    }
}
