import Foundation

/// Which text color is readable on an accent surface.
///
/// macOS writes white on accent surfaces. With a yellow accent, white on it
/// is barely readable - visual check 14.09.
/// Hence: from a relative luminance of 0.5, dark text. The WCAG threshold
/// (0.18) would already give Apple's blue dark text, which doesn't look
/// like macOS; at 0.5, only yellow among the system colors is affected.
public enum AccentContrast {
    public static let threshold = 0.5

    /// Relative luminance per WCAG from sRGB components 0...1.
    public static func luminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public static func prefersDarkForeground(red: Double, green: Double, blue: Double) -> Bool {
        luminance(red: red, green: green, blue: blue) >= threshold
    }
}
