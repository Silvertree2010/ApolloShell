import CoreGraphics
import Foundation

public struct ScreenInfo: Equatable, Sendable, Identifiable {
    public var name: String
    public var frame: CGRect
    public var isPrimary: Bool

    public init(name: String, frame: CGRect, isPrimary: Bool) {
        self.name = name
        self.frame = frame
        self.isPrimary = isPrimary
    }

    public var key: String { ScreenInfo.key(name: name, frame: frame) }

    public var id: String { key }

    public static func key(name: String, frame: CGRect) -> String {
        "\(name) \(Int(frame.width.rounded()))x\(Int(frame.height.rounded()))"
    }
}

public enum ScreenChoice: Equatable, Hashable, Sendable {
    case all
    case primary
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

    private var screenKey: String? {
        switch self {
        case .single(let key): key
        case .all, .primary: nil
        }
    }

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

public enum ScreenSelection {
    public static func targets(among screens: [ScreenInfo], choice: ScreenChoice) -> [ScreenInfo] {
        guard !screens.isEmpty else { return [] }
        switch choice {
        case .all:
            return screens
        case .primary:
            return primary(among: screens).map { [$0] } ?? []
        case .single(let key):
            if let hit = screens.first(where: { $0.key == key }) { return [hit] }
            return primary(among: screens).map { [$0] } ?? []
        }
    }

    public static func primary(among screens: [ScreenInfo]) -> ScreenInfo? {
        screens.first { $0.isPrimary } ?? screens.first
    }

    public static func screen(at point: CGPoint, among screens: [ScreenInfo]) -> ScreenInfo? {
        guard !screens.isEmpty else { return nil }
        if let hit = screens.first(where: { $0.frame.contains(point) }) { return hit }
        return screens.min { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
