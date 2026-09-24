import Foundation

public struct AppVersion: Equatable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let numbers: [Int]
    public let prerelease: String

    public init?(_ text: String) {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.first == "v" || body.first == "V" { body.removeFirst() }
        if let plus = body.firstIndex(of: "+") { body = String(body[body.startIndex..<plus]) }
        let head: Substring
        if let dash = body.firstIndex(of: "-") {
            head = body[body.startIndex..<dash]
            prerelease = String(body[body.index(after: dash)...])
        } else {
            head = body[...]
            prerelease = ""
        }
        let parts = head.split(separator: ".", omittingEmptySubsequences: false)
        var numbers: [Int] = []
        for part in parts {
            guard let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        guard !numbers.isEmpty else { return nil }
        self.numbers = numbers
    }

    public var description: String {
        let head = numbers.map(String.init).joined(separator: ".")
        return prerelease.isEmpty ? head : "\(head)-\(prerelease)"
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.padded(to: rhs) == rhs.padded(to: lhs) && lhs.prerelease == rhs.prerelease
    }

    public func hash(into hasher: inout Hasher) {
        var numbers = numbers
        while numbers.last == 0 { numbers.removeLast() }
        hasher.combine(numbers)
        hasher.combine(prerelease)
    }

    private func padded(to other: AppVersion) -> [Int] {
        numbers + Array(repeating: 0, count: max(0, other.numbers.count - numbers.count))
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for index in 0..<count {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right }
        }
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (true, false): return false
        case (false, true): return true
        case (false, false): return lhs.prerelease.compare(rhs.prerelease, options: .numeric) == .orderedAscending
        }
    }
}
