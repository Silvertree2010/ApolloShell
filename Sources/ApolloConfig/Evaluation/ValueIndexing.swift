enum ValueIndexing {
    static let limit = 1_000_000_000.0

    static func wholeNumber(_ number: Double) -> Int? {
        guard number.rounded() == number, Swift.abs(number) <= limit else { return nil }
        return Int(number)
    }

    static func element<T>(_ items: [T], _ position: Int) -> T? {
        let resolved = position < 0 ? items.count + position : position
        return items.indices.contains(resolved) ? items[resolved] : nil
    }
}
