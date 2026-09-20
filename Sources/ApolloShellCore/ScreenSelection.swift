import CoreGraphics
import Foundation

/// A screen the way the selection sees it: name, frame, and whether it is the
/// main screen (the one with the menu bar).
///
/// Without AppKit on purpose: the whole selection is plain arithmetic and can
/// be checked without windows and without a cable plugged in. The app builds
/// the list out of `NSScreen.screens`.
public struct ScreenInfo: Equatable, Sendable, Identifiable {
    public var name: String
    /// The whole frame in AppKit coordinates (origin at the bottom left of the
    /// main screen, y upwards).
    public var frame: CGRect
    /// The screen with the menu bar. In `NSScreen.screens` that is the first
    /// one; with several, only one counts as the main screen all the same.
    public var isPrimary: Bool

    public init(name: String, frame: CGRect, isPrimary: Bool) {
        self.name = name
        self.frame = frame
        self.isPrimary = isPrimary
    }

    /// A stable key a setting remembers a single screen under: the name plus
    /// the resolution.
    ///
    /// Why not the display ID: macOS hands that out anew when a screen is
    /// plugged in, and a remembered screen would be a different one after
    /// every replug. Name and resolution survive that.
    ///
    /// The price: two identical screens with the same resolution have the same
    /// key and cannot be told apart by the setting - then the first one counts
    /// (see `ScreenSelection.targets`).
    public var key: String { ScreenInfo.key(name: name, frame: frame) }

    public var id: String { key }

    /// Rounded to whole points: a resolution with decimals (scaled modes)
    /// would otherwise give a different key on every wake-up of the
    /// machine.
    public static func key(name: String, frame: CGRect) -> String {
        "\(name) \(Int(frame.width.rounded()))x\(Int(frame.height.rounded()))"
    }
}

/// Which screens the bar stands on (Nexus > Bar).
public enum ScreenChoice: Equatable, Hashable, Sendable {
    /// On every connected screen. The default.
    case all
    /// Only on the screen with the menu bar.
    case primary
    /// Only on one particular screen, remembered through `ScreenInfo.key`.
    /// When it is not there, it falls back to the main screen.
    case single(String)
}

extension ScreenChoice: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode, screen
    }

    private enum Mode: String, Codable {
        case all, primary, single
    }

    private var mode: Mode {
        switch self {
        case .all: .all
        case .primary: .primary
        case .single: .single
        }
    }

    /// A key only with `.single`, otherwise `null` - that way it stands in the
    /// file and whoever edits it by hand finds it.
    private var screenKey: String? {
        switch self {
        case .single(let key): key
        case .all, .primary: nil
        }
    }

    /// Lenient like the rest of settings.json: unknown or missing entries give
    /// the default. `single` without a usable key is no selection but a broken
    /// line - so the default as well.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mode = (try? c.decodeIfPresent(Mode.self, forKey: .mode)) ?? nil
        let key = (((try? c.decodeIfPresent(String.self, forKey: .screen)) ?? nil))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .primary:
            self = .primary
        case .single:
            guard let key, !key.isEmpty else {
                self = .all
                return
            }
            self = .single(key)
        case .all, nil:
            self = .all
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(screenKey, forKey: .screen)
    }
}

/// Which screens get something and which one lies under the pointer.
///
/// The whole screen decision of the shell stands here, so that it is testable
/// without windows: the app only builds windows around the frames that come
/// out of it.
public enum ScreenSelection {
    /// The screens the bar should stand on.
    ///
    /// An empty list (a cable in the middle of being replugged, all screens
    /// asleep): an empty result. The app then leaves standing what stands,
    /// instead of tearing everything down and building it up again at once.
    public static func targets(among screens: [ScreenInfo], choice: ScreenChoice) -> [ScreenInfo] {
        guard !screens.isEmpty else { return [] }
        switch choice {
        case .all:
            return screens
        case .primary:
            return primary(among: screens).map { [$0] } ?? []
        case .single(let key):
            // With two identical screens (the same key) the first one -
            // "a single screen" should stay one.
            if let hit = screens.first(where: { $0.key == key }) { return [hit] }
            // The remembered screen is not there: the main screen.
            return primary(among: screens).map { [$0] } ?? []
        }
    }

    /// The screen with the menu bar; without a mark, the first one.
    public static func primary(among screens: [ScreenInfo]) -> ScreenInfo? {
        screens.first { $0.isPrimary } ?? screens.first
    }

    /// The screen under the pointer.
    ///
    /// Exactly on the edge between two screens, the one whose frame holds
    /// the point wins: `CGRect.contains` counts the left and the bottom edge
    /// in, the right and the top one not. So two screens side by side share
    /// no point, and the answer is unambiguous instead of depending on the
    /// order.
    ///
    /// When the point lies on no screen (right at the top edge, or in a gap
    /// between screens arranged with an offset), the nearest one counts - the
    /// pointer is visibly somewhere, after all.
    public static func screen(at point: CGPoint, among screens: [ScreenInfo]) -> ScreenInfo? {
        guard !screens.isEmpty else { return nil }
        if let hit = screens.first(where: { $0.frame.contains(point) }) { return hit }
        return screens.min { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }
    }

    /// The squared distance from the point to the nearest point of the frame
    /// (0 when it lies inside). Squared is enough for the comparison and saves
    /// the square root.
    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
