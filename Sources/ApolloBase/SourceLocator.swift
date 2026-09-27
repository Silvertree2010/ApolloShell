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
        var result: [Int: SourcePosition] = [:]
        result.reserveCapacity(offsets.count)
        var graphemeEnds: [Int: [Int]?] = [:]
        for raw in offsets {
            let offset = max(0, min(raw, utf8.count))
            if result[offset] != nil { continue }
            let line = lineNumber(atByteOffset: offset)
            let start = lineStarts[line - 1]
            let end = lineEnds[line - 1]
            let relative = min(offset, end) - start
            let column: Int
            let ends: [Int]?
            if let cached = graphemeEnds[line] {
                ends = cached
            } else {
                ends = lineGraphemeEnds(start: start, end: end)
                graphemeEnds[line] = .some(ends)
            }
            if let ends {
                var low = 0
                var high = ends.count
                while low < high {
                    let middle = (low + high) / 2
                    if ends[middle] <= relative {
                        low = middle + 1
                    } else {
                        high = middle
                    }
                }
                column = low + 1
            } else {
                column = relative + 1
            }
            result[offset] = SourcePosition(offset: offset, line: line, column: column)
        }
        return result
    }

    private func lineGraphemeEnds(start: Int, end: Int) -> [Int]? {
        guard utf8[start..<end].contains(where: { $0 >= 0x80 }) else { return nil }
        var ends: [Int] = []
        var consumed = 0
        for character in String(decoding: utf8[start..<end], as: UTF8.self) {
            consumed += character.utf8.count
            ends.append(consumed)
        }
        return ends
    }
}
