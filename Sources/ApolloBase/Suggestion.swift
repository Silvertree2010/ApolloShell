public enum Suggestion {
    public static func closest(to word: String, among candidates: [String], maxDistance: Int = 2) -> String? {
        let wordCharacters = Array(word)
        var best: String?
        var bestDistance = maxDistance + 1
        for candidate in candidates {
            let candidateCharacters = Array(candidate)
            guard abs(candidateCharacters.count - wordCharacters.count) < bestDistance else { continue }
            let distance = editDistance(wordCharacters, candidateCharacters)
            if distance < bestDistance {
                best = candidate
                bestDistance = distance
            }
        }
        return best
    }

    static func editDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)
        for i in 1...lhs.count {
            current[0] = i
            for j in 1...rhs.count {
                let substitution = previous[j - 1] + (lhs[i - 1] == rhs[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }
}
