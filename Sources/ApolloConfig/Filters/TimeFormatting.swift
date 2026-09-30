import Foundation

enum DurationText {
    static func clock(_ seconds: Double) -> String {
        let total = Int(Swift.abs(seconds).rounded(.down))
        let sign = seconds < 0 && total > 0 ? "-" : ""
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let rest = total % 60
        if hours > 0 {
            return sign + "\(hours):" + twoDigits(minutes) + ":" + twoDigits(rest)
        }
        return sign + "\(minutes):" + twoDigits(rest)
    }

    static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

enum DateText {
    static func format(_ date: Date, pattern: String, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = expand(pattern, locale: locale)
        return formatter.string(from: date)
    }

    static func expand(_ pattern: String, locale: Locale) -> String {
        guard pattern.contains("j") else { return pattern }
        var out = "", quoted = false, run = 0
        func flush() {
            guard run > 0 else { return }
            let skeleton = DateFormatter.dateFormat(fromTemplate: String(repeating: "j", count: run), options: 0, locale: locale) ?? ""
            let letter = skeleton.first { "hHkK".contains($0) } ?? "H"
            out += String(repeating: letter, count: run)
            run = 0
        }
        for c in pattern {
            if c == "'" { flush(); quoted.toggle(); out.append(c) }
            else if c == "j" && !quoted { run += 1 }
            else { flush(); out.append(c) }
        }
        flush()
        return out
    }

    static func relative(_ date: Date, now: Date) -> String {
        let delta = date.timeIntervalSince(now)
        let seconds = Swift.abs(delta)
        guard seconds >= 60 else { return "now" }
        let amount: String
        if seconds < 3600 {
            amount = "\(Int(seconds / 60)) min"
        } else if seconds < 86_400 {
            amount = "\(Int(seconds / 3600)) h"
        } else {
            amount = "\(Int(Swift.min(seconds / 86_400, 1_000_000_000))) d"
        }
        return delta > 0 ? "in \(amount)" : "\(amount) ago"
    }
}
