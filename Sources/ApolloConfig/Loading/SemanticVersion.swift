enum SemanticVersion {
    static func components(_ text: String) -> [Int]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var result: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            result.append(value)
        }
        return result
    }

    static func compare(_ lhs: String, _ rhs: String) -> Int? {
        guard let a = components(lhs), let b = components(rhs) else { return nil }
        let count = max(a.count, b.count)
        for index in 0..<count {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}
