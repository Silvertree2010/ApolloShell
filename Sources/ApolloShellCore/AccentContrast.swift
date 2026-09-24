import Foundation

public enum AccentContrast {
    public static let threshold = 0.5

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
