import Foundation

extension NumberText {
    static func rounded(_ number: Double, digits: Int) -> Double {
        let factor = pow(10, Double(digits))
        let scaled = number * factor
        guard scaled.isFinite else { return number }
        let result = scaled.rounded(.toNearestOrAwayFromZero) / factor
        return result == 0 ? 0 : result
    }

    static func fixed(_ number: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), rounded(number, digits: digits))
    }

    static func grouped(_ number: Double, digits: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: rounded(number, digits: digits))) ?? plain(number)
    }
}
