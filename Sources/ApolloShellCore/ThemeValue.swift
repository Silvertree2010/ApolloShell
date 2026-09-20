import Foundation

/// A color out of a theme: sRGB parts and opacity, each 0...1.
///
/// A type of its own instead of NSColor/Color, because the core builds
/// without a user interface and because values out of other files have to
/// be clamped before they arrive: `init` catches NaN, infinity and 0...1.
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

    /// 0xRRGGBB - the spelling of the defaults in the token catalogue.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    /// NaN and infinity do not exist in a color: they would end up in
    /// CoreGraphics later and make areas disappear there.
    ///
    /// Rounded to 8 bits on top of that - exactly the way a color stands in
    /// the file too. So writing and reading back gives the same color, and
    /// `cssText` is no approximation but the value itself.
    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (min(max(value, 0), 1) * 255).rounded() / 255
    }

    public static let black = ThemeColor(hex: 0x000000)
    public static let white = ThemeColor(hex: 0xFFFFFF)
    public static let clear = ThemeColor(red: 0, green: 0, blue: 0, alpha: 0)

    /// `#rrggbb`, with opacity `#rrggbbaa`. This spelling stands in the docs
    /// and in the example themes - it can be read back in.
    public var cssText: String {
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        let rgb = String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
        return alpha >= 1 ? rgb : rgb + String(format: "%02x", byte(alpha))
    }

    /// Relative luminance per WCAG - the same arithmetic as for the text
    /// color on accent areas.
    public var luminance: Double {
        AccentContrast.luminance(red: red, green: green, blue: blue)
    }

    /// Contrast ratio per WCAG, 1...21. Both colors should be opaque;
    /// otherwise `composited(over:)` first.
    public static func contrast(_ one: ThemeColor, _ other: ThemeColor) -> Double {
        let a = one.luminance
        let b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// This color with its opacity laid over an (opaque) area.
    public func composited(over background: ThemeColor) -> ThemeColor {
        guard alpha < 1 else { return self }
        func mix(_ top: Double, _ bottom: Double) -> Double { top * alpha + bottom * (1 - alpha) }
        return ThemeColor(red: mix(red, background.red),
                          green: mix(green, background.green),
                          blue: mix(blue, background.blue),
                          alpha: 1)
    }

    /// Moved linearly towards `other`, the opacity stays. `amount` 0...1.
    public func blended(with other: ThemeColor, amount: Double) -> ThemeColor {
        let t = ThemeColor.unit(amount)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return ThemeColor(red: mix(red, other.red),
                          green: mix(green, other.green),
                          blue: mix(blue, other.blue),
                          alpha: alpha)
    }

    /// With a different opacity.
    public func withAlpha(_ value: Double) -> ThemeColor {
        ThemeColor(red: red, green: green, blue: blue, alpha: value)
    }
}

/// Unit of a number in the theme. `px` and `pt` are the same for us: the
/// shell works in points, and a theme should not have to know which screen
/// it ends up on.
public enum ThemeUnit: String, Equatable, Hashable, Sendable, CaseIterable {
    /// A length in points - `12px`, `12pt` or `12`.
    case points
    /// A fraction 0...1 - `0.5` or `50%`.
    case ratio
    /// A plain number without a unit - `400`.
    case scalar

    /// How a number of this unit is written (docs, examples).
    public func cssText(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        // Whole numbers without ".0" - but only while they fit in Int. A
        // theme may write numbers of any size in there, and those end up
        // here in the notice before they are clamped.
        let digits = rounded.isFinite && rounded == rounded.rounded() && rounded.magnitude < 1e15
            ? String(Int(rounded))
            : String(rounded.isFinite ? rounded : value)
        return self == .points ? digits + "px" : digits
    }
}

/// A file out of the theme folder. `url` is `nil` while nothing has been
/// checked or the check failed - then the default applies (no image).
public struct ThemeAsset: Equatable, Hashable, Sendable {
    /// The way it stands in the theme, only for display and error messages.
    public let reference: String
    /// The checked file: it exists, lies in the theme folder, is not too big.
    public let url: URL?

    public init(reference: String, url: URL?) {
        self.reference = reference
        self.url = url
    }

    public static let none = ThemeAsset(reference: "", url: nil)
}

/// A color gradient out of a theme.
///
/// A gradient is always straight (`linear-gradient`): that is enough for the
/// areas of a shell, and what does not exist cannot break either.
/// `none` - so no gradient - is the normal case; then the color next to it
/// colors the area as before.
///
/// The angle follows CSS: 0 degrees points up, 90 degrees to the right.
public struct ThemeGradient: Equatable, Hashable, Sendable {
    /// One color at one spot of the gradient, 0...1.
    public struct Stop: Equatable, Hashable, Sendable {
        public let color: ThemeColor
        public let position: Double

        public init(color: ThemeColor, position: Double) {
            self.color = color
            self.position = position.isFinite ? min(max(position, 0), 1) : 0
        }
    }

    /// At most this many color stops. No area needs more, and the limit
    /// keeps a file from grinding the drawing to a halt.
    public static let maximumStops = 8

    public let angle: Double
    public let stops: [Stop]

    public init(angle: Double = 180, stops: [Stop]) {
        self.angle = angle.isFinite ? angle.truncatingRemainder(dividingBy: 360) : 180
        self.stops = Array(stops.prefix(ThemeGradient.maximumStops))
    }

    /// No gradient. Then the color of the token next to it applies.
    public static let none = ThemeGradient(stops: [])

    /// A gradient needs at least two colors; anything else is none.
    public var isEmpty: Bool { stops.count < 2 }

    /// Start and end of the gradient in unit coordinates (0,0 = top left,
    /// 1,1 = bottom right) - the shape SwiftUI and CoreGraphics need.
    /// brauchen.
    ///
    /// The angle follows CSS: 0 degrees points up, 90 degrees to the right,
    /// 180 degrees down. The first color stands where the gradient begins:
    /// at 180 degrees that is the top.
    public var points: (start: (x: Double, y: Double), end: (x: Double, y: Double)) {
        // The direction in screen coordinates: y grows downwards, so
        // "upwards" is negative.
        let radians = (angle - 90) * .pi / 180
        let dx = cos(radians) / 2
        let dy = sin(radians) / 2
        return (start: (x: 0.5 - dx, y: 0.5 - dy), end: (x: 0.5 + dx, y: 0.5 + dy))
    }

    /// `none` oder `linear-gradient(180deg, #111111 0%, #333333 100%)`.
    public var cssText: String {
        guard !isEmpty else { return "none" }
        let parts = stops.map { stop in
            "\(stop.color.cssText) \(Int((stop.position * 100).rounded()))%"
        }
        return "linear-gradient(\(ThemeUnit.scalar.cssText(angle))deg, \(parts.joined(separator: ", ")))"
    }
}

/// The value of a token, already checked and in the unit of the token.
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
