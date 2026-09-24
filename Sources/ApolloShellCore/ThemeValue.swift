import Foundation

public struct ThemeColor: Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = ThemeColor.unit(red)
        self.green = ThemeColor.unit(green)
        self.blue = ThemeColor.unit(blue)
        self.alpha = ThemeColor.unit(alpha)
    }

    public init(hex: UInt32, alpha: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (min(max(value, 0), 1) * 255).rounded() / 255
    }

    public static let black = ThemeColor(hex: 0x000000)
    public static let white = ThemeColor(hex: 0xFFFFFF)
    public static let clear = ThemeColor(red: 0, green: 0, blue: 0, alpha: 0)

    public var cssText: String {
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        let rgb = String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
        return alpha >= 1 ? rgb : rgb + String(format: "%02x", byte(alpha))
    }

    public var luminance: Double {
        AccentContrast.luminance(red: red, green: green, blue: blue)
    }

    public static func contrast(_ one: ThemeColor, _ other: ThemeColor) -> Double {
        let a = one.luminance
        let b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    public func composited(over background: ThemeColor) -> ThemeColor {
        guard alpha < 1 else { return self }
        func mix(_ top: Double, _ bottom: Double) -> Double { top * alpha + bottom * (1 - alpha) }
        return ThemeColor(red: mix(red, background.red),
                          green: mix(green, background.green),
                          blue: mix(blue, background.blue),
                          alpha: 1)
    }

    public func blended(with other: ThemeColor, amount: Double) -> ThemeColor {
        let t = ThemeColor.unit(amount)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return ThemeColor(red: mix(red, other.red),
                          green: mix(green, other.green),
                          blue: mix(blue, other.blue),
                          alpha: alpha)
    }

    public func withAlpha(_ value: Double) -> ThemeColor {
        ThemeColor(red: red, green: green, blue: blue, alpha: value)
    }
}

public enum ThemeUnit: String, Equatable, Hashable, Sendable, CaseIterable {
    case points
    case ratio
    case scalar

    public func cssText(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        let digits = rounded.isFinite && rounded == rounded.rounded() && rounded.magnitude < 1e15
            ? String(Int(rounded))
            : String(rounded.isFinite ? rounded : value)
        return self == .points ? digits + "px" : digits
    }
}

public struct ThemeAsset: Equatable, Hashable, Sendable {
    public let reference: String
    public let url: URL?

    public init(reference: String, url: URL?) {
        self.reference = reference
        self.url = url
    }

    public static let none = ThemeAsset(reference: "", url: nil)
}

public struct ThemeGradient: Equatable, Hashable, Sendable {
    public struct Stop: Equatable, Hashable, Sendable {
        public let color: ThemeColor
        public let position: Double

        public init(color: ThemeColor, position: Double) {
            self.color = color
            self.position = position.isFinite ? min(max(position, 0), 1) : 0
        }
    }

    public static let maximumStops = 8

    public let angle: Double
    public let stops: [Stop]

    public init(angle: Double = 180, stops: [Stop]) {
        self.angle = angle.isFinite ? angle.truncatingRemainder(dividingBy: 360) : 180
        self.stops = Array(stops.prefix(ThemeGradient.maximumStops))
    }

    public static let none = ThemeGradient(stops: [])

    public var isEmpty: Bool { stops.count < 2 }

    public var points: (start: (x: Double, y: Double), end: (x: Double, y: Double)) {
        let radians = (angle - 90) * .pi / 180
        let dx = cos(radians) / 2
        let dy = sin(radians) / 2
        return (start: (x: 0.5 - dx, y: 0.5 - dy), end: (x: 0.5 + dx, y: 0.5 + dy))
    }

    public var cssText: String {
        guard !isEmpty else { return "none" }
        let parts = stops.map { stop in
            "\(stop.color.cssText) \(Int((stop.position * 100).rounded()))%"
        }
        return "linear-gradient(\(ThemeUnit.scalar.cssText(angle))deg, \(parts.joined(separator: ", ")))"
    }
}

public enum ThemeValue: Equatable, Hashable, Sendable {
    case color(ThemeColor)
    case gradient(ThemeGradient)
    case number(Double)
    case text(String)
    case file(ThemeAsset)
    case option(String)
    case flag(Bool)

    public var color: ThemeColor? { if case let .color(value) = self { value } else { nil } }
    public var gradient: ThemeGradient? { if case let .gradient(value) = self { value } else { nil } }
    public var number: Double? { if case let .number(value) = self { value } else { nil } }
    public var text: String? { if case let .text(value) = self { value } else { nil } }
    public var asset: ThemeAsset? { if case let .file(value) = self { value } else { nil } }
    public var option: String? { if case let .option(value) = self { value } else { nil } }
    public var flag: Bool? { if case let .flag(value) = self { value } else { nil } }
}
