enum KDLLineRange {
    enum Tail: Equatable {
        case lineEnd(contentEnd: Int, afterBreak: Int)
        case endOfFile(Int)
        case sameLine(Int)
    }

    struct Layout: Equatable {
        let start: Int
        let end: Int
        let lineStart: Int
        let lineIndent: String
        let indentOnly: Bool
        let tail: Tail

        var ownLine: Bool {
            guard indentOnly else { return false }
            if case .sameLine = tail {
                return false
            }
            return true
        }

        var range: Range<Int> {
            switch tail {
            case .lineEnd(let contentEnd, let afterBreak):
                return ownLine ? lineStart..<afterBreak : start..<contentEnd
            case .endOfFile(let fileEnd):
                return (ownLine ? lineStart : start)..<fileEnd
            case .sameLine(let next):
                return start..<next
            }
        }
    }

    static func layout(in source: KDLSource, start: Int, end: Int) -> Layout {
        let lineStart = source.lineStart(before: start)
        var indentEnd = lineStart
        while let decoded = source.decoded(at: indentEnd), KDLCharacters.isUnicodeSpace(decoded.scalar) {
            indentEnd += decoded.length
        }
        return Layout(
            start: start,
            end: end,
            lineStart: lineStart,
            lineIndent: source.string(from: lineStart, to: indentEnd),
            indentOnly: indentEnd == start,
            tail: tail(in: source, from: end)
        )
    }

    static func range(in source: KDLSource, start: Int, end: Int) -> Range<Int> {
        layout(in: source, start: start, end: end).range
    }

    static func tail(in source: KDLSource, from end: Int) -> Tail {
        var index = skipInlineSpace(in: source, from: end)
        if source.byte(at: index) == UInt8(ascii: ";") {
            index = skipInlineSpace(in: source, from: index + 1)
        }
        if source.hasPrefix("//", at: index) {
            while let decoded = source.decoded(at: index), !KDLCharacters.isNewline(decoded.scalar) {
                index += decoded.length
            }
        }
        guard index < source.count else { return .endOfFile(index) }
        if let length = source.newlineLength(at: index) {
            return .lineEnd(contentEnd: index, afterBreak: index + length)
        }
        return .sameLine(index)
    }

    static func skipInlineSpace(in source: KDLSource, from offset: Int) -> Int {
        var index = offset
        while index < source.count {
            if let decoded = source.decoded(at: index), KDLCharacters.isUnicodeSpace(decoded.scalar) {
                index += decoded.length
            } else if source.hasPrefix("/*", at: index), let after = blockCommentEnd(in: source, from: index) {
                index = after
            } else {
                return index
            }
        }
        return index
    }

    static func blockCommentEnd(in source: KDLSource, from offset: Int) -> Int? {
        var index = offset + 2
        var depth = 1
        while index < source.count {
            if source.hasPrefix("/*", at: index) {
                depth += 1
                index += 2
            } else if source.hasPrefix("*/", at: index) {
                depth -= 1
                index += 2
                if depth == 0 {
                    return index
                }
            } else {
                index += 1
            }
        }
        return nil
    }
}
