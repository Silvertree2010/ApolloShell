import Foundation

enum NumberText {
    static func plain(_ number: Double) -> String {
        if number == number.rounded(), Swift.abs(number) < 1e15 {
            return String(Int64(number))
        }
        return "\(number)"
    }
}
