import Foundation

/// Welche Schriftfarbe auf einer Akzentflaeche lesbar ist.
///
/// macOS schreibt auf Akzentflaechen weiss. Bei gelbem Akzent ist weiss
/// darauf kaum zu lesen - Bildprobe 14.09.
/// Deshalb: ab einer relativen Helligkeit von 0,5 dunkle Schrift. Die
/// WCAG-Grenze (0,18) wuerde schon Apples Blau dunkel beschriften, das
/// sieht nicht nach macOS aus; bei 0,5 trifft es von den Systemfarben nur
/// Gelb.
public enum AccentContrast {
    public static let threshold = 0.5

    /// Relative Helligkeit nach WCAG aus sRGB-Anteilen 0...1.
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
