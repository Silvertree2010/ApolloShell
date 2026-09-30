import Foundation

public enum SunMoon {
    public struct Day: Equatable, Sendable {
        public var sunrise: Date?
        public var sunset: Date?
        public var noon: Date
        public var alwaysUp: Bool
    }

    private static let unixJulian = 2_440_587.5
    private static let j2000 = 2_451_545.0
    public static let synodicMonth = 29.530588853
    private static let knownNewMoon = 2_451_550.26

    private static func julian(_ date: Date) -> Double { date.timeIntervalSince1970 / 86_400 + unixJulian }
    private static func moment(julian: Double) -> Date { Date(timeIntervalSince1970: (julian - unixJulian) * 86_400) }
    private static func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func deg(_ radians: Double) -> Double { radians * 180 / .pi }

    public static func day(_ date: Date, latitude: Double, longitude: Double) -> Day {
        let n = (julian(date) - j2000 + 0.0008 - longitude / 360).rounded()
        let meanNoon = n - longitude / 360
        let anomaly = (357.5291 + 0.98560028 * meanNoon).truncatingRemainder(dividingBy: 360)
        let m = rad(anomaly)
        let center = 1.9148 * sin(m) + 0.0200 * sin(2 * m) + 0.0003 * sin(3 * m)
        let lambda = rad((anomaly + center + 180 + 102.9372).truncatingRemainder(dividingBy: 360))
        let transit = j2000 + meanNoon + 0.0053 * sin(m) - 0.0069 * sin(2 * lambda)
        let declination = asin(sin(lambda) * sin(rad(23.4397)))
        let phi = rad(latitude)
        let cosHour = (sin(rad(-0.833)) - sin(phi) * sin(declination)) / (cos(phi) * cos(declination))
        let noon = moment(julian: transit)
        guard cosHour >= -1, cosHour <= 1 else {
            return Day(sunrise: nil, sunset: nil, noon: noon, alwaysUp: cosHour < -1)
        }
        let hour = deg(acos(cosHour)) / 360
        return Day(sunrise: moment(julian: transit - hour), sunset: moment(julian: transit + hour), noon: noon, alwaysUp: false)
    }

    public static func moonPhase(_ date: Date) -> Double {
        let cycles = (julian(date) - knownNewMoon) / synodicMonth
        return cycles - cycles.rounded(.down)
    }

    public static func illumination(phase: Double) -> Double { (1 - cos(2 * .pi * phase)) / 2 }

    public static func moonSymbol(phase: Double) -> String {
        let names = ["moonphase.new.moon", "moonphase.waxing.crescent", "moonphase.first.quarter",
                     "moonphase.waxing.gibbous", "moonphase.full.moon", "moonphase.waning.gibbous",
                     "moonphase.last.quarter", "moonphase.waning.crescent"]
        return names[Int((phase * 8).rounded()) % 8]
    }

    public static func moonName(phase: Double) -> String {
        ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous", "Full Moon",
         "Waning Gibbous", "Last Quarter", "Waning Crescent"][Int((phase * 8).rounded()) % 8]
    }

    public static func record(_ date: Date, latitude: Double, longitude: Double) -> Value {
        let day = day(date, latitude: latitude, longitude: longitude)
        let phase = moonPhase(date)
        return .record(Record([
            ("sunrise", day.sunrise.map { Value.date($0) } ?? .null),
            ("sunset", day.sunset.map { Value.date($0) } ?? .null),
            ("noon", .date(day.noon)),
            ("always-up", .bool(day.alwaysUp)),
            ("always-down", .bool(day.sunrise == nil && !day.alwaysUp)),
            ("moonrise", .null),
            ("moonset", .null),
            ("moon-phase", .number(phase)),
            ("moon-illumination", .number(illumination(phase: phase))),
            ("moon-symbol", .string(moonSymbol(phase: phase))),
            ("moon-name", .string(moonName(phase: phase))),
        ]))
    }
}
