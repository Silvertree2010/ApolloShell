import Foundation

/// A version of the app the way it stands in `CFBundleShortVersionString`
/// ("0.1.2") or as a Git tag ("v0.1.2").
///
/// Only as much semver as the shell needs: the numbers are compared from left
/// to right, and missing places count as 0 ("0.1" == "0.1.0"). An addition
/// behind a hyphen ("0.2.0-beta.1") counts as a prerelease and is OLDER than
/// the same version without it - the way semver prescribes it and Sparkle
/// handles it too.
///
/// The unknown is not guessed: when no number stands there, there is no
/// version, and the caller reports nothing rather than something wrong.
public struct AppVersion: Equatable, Hashable, Sendable, Comparable, CustomStringConvertible {
    /// The numbers before a possible addition, at least one.
    public let numbers: [Int]
    /// The addition behind the first hyphen, without it; otherwise empty.
    public let prerelease: String

    public init?(_ text: String) {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.first == "v" || body.first == "V" { body.removeFirst() }
        // Build metadata ("+35") plays no part in the order.
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

    /// Equal means: the same order. "0.1" and "0.1.0" are the same version -
    /// were that only so when comparing and not when equating, the two would
    /// contradict each other.
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
        // Without an addition it is the finished version, which stands behind the prerelease.
        case (true, false): return false
        case (false, true): return true
        case (false, false): return lhs.prerelease.compare(rhs.prerelease, options: .numeric) == .orderedAscending
        }
    }
}
