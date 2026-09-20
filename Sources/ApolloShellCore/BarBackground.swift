import Foundation

/// What the bar and its bulge are backed with (Nexus > Bar > Background).
/// Hintergrund).
/// Why there is a choice at all: Liquid Glass in the `regular` version follows
/// the brightness of what lies behind it, and while doing so it also flips
/// between a light and a dark appearance - explicitly regardless of whether
/// the system stands on light or dark (Apple, WWDC25 "Meet Liquid Glass":
/// "constantly adapt their appearance depending on what's behind them ... flip
/// from light to dark based on the background"). So the bar recolors itself as
/// soon as a window moves under it.
///
/// faehrt.
///
/// It cannot be switched off: the whole interface for it is NSGlassEffectView
/// (contentView, cornerRadius, effectIsInteractive, style with regular/clear)
/// and SwiftUI's `Glass` (regular, clear, identity, tint, interactive) - no
/// switch for the adaptation. Tinting only helps so far, because the tones are
/// mapped onto the brightness of the background too ("Selecting a color
/// generates a range of tones that are mapped to content brightness
/// underneath").
///
/// What can be steered is only what lies behind the glass. That is what the
/// entries come down to: `material` replaces the glass with a system material
/// with a fixed appearance per light/dark, and `fixedGlass` lays an opaque area
/// under the glass and takes the `clear` version for it, which according to
/// Apple has no adapting behavior at all ("Clear ... does not have adaptive
/// behaviors ... it needs a dimming layer") - the opaque area is that layer.
/// Schicht.
public enum BarBackground: String, Codable, CaseIterable, Sendable, Identifiable {
    /// A system material instead of glass: one color per appearance, changes
    /// with light/dark like an ordinary window. The default.
    case material
    /// Liquid Glass, the `regular` version - adapts to what lies behind it.
    case glass
    /// Liquid Glass, the `regular` version, tinted in the window color.
    case tintedGlass
    /// Clear Liquid Glass over an opaque area in the window color.
    case fixedGlass

    public var id: Self { self }

    /// Without a setting: material - the state before this choice existed.
    public static let standard = material

    /// Lenient like the rest of settings.json: an unknown or mistyped value is
    /// the default, not an error.
    public init(from decoder: any Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = raw.flatMap(BarBackground.init(rawValue:)) ?? .standard
    }
}
