import Foundation
import ApolloShellCore

public struct DefaultFilterServices: FilterServices {
    let calendar: Calendar

    public init() {
        self.init(calendar: .autoupdatingCurrent)
    }

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    public func appSearch(_ apps: [Value], query: String) -> [Value] {
        var entries: [AppEntry] = []
        var positions: [AppEntry: [Int]] = [:]
        var weights: [String: Double] = [:]
        var favorites: [(position: Double, key: String)] = []
        for (index, app) in apps.enumerated() {
            guard case .record(let record) = app else { continue }
            let path = Self.text(record["path"]) ?? "/.apolloshell-app-\(index)"
            let entry = AppEntry(
                name: Self.text(record["name"]) ?? "",
                url: URL(fileURLWithPath: path),
                bundleID: Self.text(record["bundle-id"])
            )
            entries.append(entry)
            positions[entry, default: []].append(index)
            if case .number(let usage)? = record["usage"], usage.isFinite {
                weights[entry.usageKey] = Swift.max(weights[entry.usageKey] ?? 0, usage)
            }
            if case .number(let position)? = record["favorite-index"], position.isFinite {
                favorites.append((position: position, key: entry.usageKey))
            }
        }
        let now = Date()
        let pinned = favorites.sorted { $0.position < $1.position }.map(\.key)
        let ranked = AppRanker().rank(entries, query: query, usage: UsageStats(weights: weights, at: now), pinned: pinned, now: now)
        var result: [Value] = []
        for entry in ranked {
            guard var queue = positions[entry], !queue.isEmpty else { continue }
            result.append(apps[queue.removeFirst()])
            positions[entry] = queue
        }
        return result
    }

    public func monthGrid(_ date: Date, offset: Int, firstWeekday: String) -> Value {
        var calendar = self.calendar
        switch firstWeekday {
        case "monday": calendar.firstWeekday = 2
        case "sunday": calendar.firstWeekday = 1
        default: break
        }
        guard let month = calendar.date(byAdding: .month, value: offset, to: date) else { return .list([]) }
        let weeks = CalendarMonth.weeks(for: month, today: date, calendar: calendar)
        let numbers = CalendarMonth.weekNumbers(weeks, calendar: calendar)
        var rows: [Value] = []
        for (week, number) in zip(weeks, numbers) {
            let days: [Value] = week.map { day in
                Value.record(Record([
                    ("day", .number(Double(day.day))),
                    ("in-month", .bool(day.inMonth)),
                    ("today", .bool(day.isToday)),
                    ("weekday", .number(Double(Self.isoWeekday(day.date, calendar: calendar)))),
                    ("week", .number(Double(number))),
                    ("date", .date(day.date)),
                ]))
            }
            rows.append(.list(days))
        }
        return .list(rows)
    }

    public func uptimeText(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? Swift.min(Swift.max(seconds, 0), 1e12) : 0
        return UptimeText.format(seconds: safe)
    }

    public func normalizedURL(_ text: String) -> String? {
        UtilitiesLink.url(from: text)?.absoluteString
    }

    public func symbolExists(_ name: String) -> Bool {
        true
    }

    public func chordDisplay(_ chord: String) -> String {
        KeyChord.parse(chord)?.display ?? chord
    }

    public func hotkeyWarning(_ chord: String) -> String? {
        guard let parsed = KeyChord.parse(chord), let warning = HotKeyAdvice.warning(for: parsed.hotKey) else { return nil }
        return HotKeyText.warning(warning)
    }

    public func temperatureText(_ celsius: Double) -> String {
        guard celsius.isFinite, Swift.abs(celsius) < 1_000_000 else { return "" }
        return WeatherText.temperature(celsius)
    }

    static func text(_ value: Value?) -> String? {
        guard case .string(let text)? = value else { return nil }
        return text
    }

    static func isoWeekday(_ date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7 + 1
    }
}
