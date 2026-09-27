public struct SourceLocator: Sendable {
    public let text: String
    private let utf8: [UInt8]
    private let lineStarts: [Int]
    private let lineEnds: [Int]

    public init(_ text: String) {
        self.text = text
        let bytes = Array(text.utf8)
        self.utf8 = bytes
        var starts = [0]
        var ends: [Int] = []
        var index = 0
        while index < bytes.count {
            let length = SourceLocator.lineBreakLength(bytes, at: index)
            if length > 0 {
                ends.append(index)
                starts.append(index + length)
                index += length
            } else {
                index += 1
            }
        }
        ends.append(bytes.count)
        self.lineStarts = starts
        self.lineEnds = ends
    }

    static func lineBreakLength(_ bytes: [UInt8], at index: Int) -> Int {
        switch bytes[index] {
        case 0x0A, 0x0C:
            return 1
        case 0x0D:
            return index + 1 < bytes.count && bytes[index + 1] == 0x0A ? 2 : 1
        case 0xC2:
            return index + 1 < bytes.count && bytes[index + 1] == 0x85 ? 2 : 0
        case 0xE2:
            guard index + 2 < bytes.count, bytes[index + 1] == 0x80 else { return 0 }
            return bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9 ? 3 : 0
        default:
            return 0
        }
    }

    public static func isLineBreak(_ character: Character) -> Bool {
        switch character.unicodeScalars.first?.value {
        case 0x0A, 0x0D, 0x0C, 0x85, 0x2028, 0x2029:
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
