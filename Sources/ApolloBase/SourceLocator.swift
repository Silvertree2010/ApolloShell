public struct SourceLocator: Sendable {
    public let text: String
    private let utf8: [UInt8]
    private let lineStarts: [Int]
    private let lineEnds: [Int]

    public init(_ text: String) {
        self.text = text
        self.utf8 = Array(text.utf8)
        var starts = [0]
        var ends: [Int] = []
        var offset = 0
        for character in text {
            let length = character.utf8.count
            if SourceLocator.isLineBreak(character) {
                ends.append(offset)
                starts.append(offset + length)
            }
            offset += length
        }
        ends.append(offset)
        self.lineStarts = starts
        self.lineEnds = ends
    }

    public static func isLineBreak(_ character: Character) -> Bool {
        switch character {
        case "\n", "\r", "\r\n", "\u{85}", "\u{0C}", "\u{2028}", "\u{2029}":
            return true
        default:
            return false
        }
    }

    public var lineCount: Int {
        lineStarts.count
    }

    public func lineText(_ line: Int) -> String? {
        guard line >= 1, line <= lineStarts.count else { return nil }
        return String(decoding: utf8[lineStarts[line - 1]..<lineEnds[line - 1]], as: UTF8.self)
    }

    public func lineNumber(atByteOffset offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lineStarts[middle] <= offset {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low + 1
    }

    public func position(atByteOffset offset: Int) -> SourcePosition {
        let clamped = max(0, min(offset, utf8.count))
        let line = lineNumber(atByteOffset: clamped)
        let relative = min(clamped, lineEnds[line - 1]) - lineStarts[line - 1]
        var consumed = 0
        var column = 1
        if relative > 0, let content = lineText(line) {
            for character in content {
                let length = character.utf8.count
                if consumed + length > relative { break }
                consumed += length
                column += 1
            }
        }
        return SourcePosition(offset: clamped, line: line, column: column)
    }

    public func positions(atByteOffsets offsets: [Int]) -> [Int: SourcePosition] {
        let wanted = Set(offsets.map { max(0, min($0, utf8.count)) }).sorted()
        var result: [Int: SourcePosition] = [:]
        result.reserveCapacity(wanted.count)
        var next = 0
        var offset = 0
        var line = 1
        var column = 1
        for character in text {
            if next == wanted.count { break }
            let length = character.utf8.count
            while next < wanted.count, wanted[next] < offset + length {
                result[wanted[next]] = SourcePosition(offset: wanted[next], line: line, column: column)
                next += 1
            }
            offset += length
            if SourceLocator.isLineBreak(character) {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        while next < wanted.count {
            result[wanted[next]] = SourcePosition(offset: wanted[next], line: line, column: column)
            next += 1
        }
        return result
    }
}
