import ApolloBase
import Dispatch
import Foundation

public enum KDLLimits {
    public static let maxBytes = 1_048_576
    public static let maxDepth = 64
}

extension KDLDocument {
    public static func parse(_ text: String, file: String) throws(KDLParseError) -> KDLDocument {
        try KDLParser.parseOnDedicatedStack(text: text, file: file)
    }
}

struct KDLParser {
    enum Entry {
        case argument(KDLValue)
        case property(KDLProperty)
    }

    let file: String
    let text: String
    let source: KDLSource
    var index = 0

    init(text: String, file: String) {
        self.file = file
        self.text = text
        self.source = KDLSource(text)
    }

    final class ResultBox: @unchecked Sendable {
        var value: Result<KDLDocument, KDLParseError>?
    }

    static func parseOnDedicatedStack(text: String, file: String) throws(KDLParseError) -> KDLDocument {
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        let thread = Thread {
            var parser = KDLParser(text: text, file: file)
            do throws(KDLParseError) {
                box.value = .success(try parser.parseDocument())
            } catch {
                box.value = .failure(error)
            }
            semaphore.signal()
        }
        thread.stackSize = 16 << 20
        thread.qualityOfService = Thread.current.qualityOfService
        thread.start()
        semaphore.wait()
        switch box.value! {
        case .success(let document):
            return document
        case .failure(let error):
            throw error
        }
    }

    mutating func parseDocument() throws(KDLParseError) -> KDLDocument {
        do throws(KDLSyntaxError) {
            let nodes = try parseAll()
            return KDLDocument(file: file, text: text, nodes: resolvePositions(nodes))
        } catch {
            let locator = SourceLocator(text)
            let span = SourceSpan(
                file: file,
                start: locator.position(atByteOffset: error.start),
                end: locator.position(atByteOffset: max(error.start, error.end))
            )
            throw KDLParseError(message: error.message, span: span)
        }
    }

    mutating func parseAll() throws(KDLSyntaxError) -> [KDLNode] {
        guard source.count <= KDLLimits.maxBytes else {
            throw KDLSyntaxError(message: "the file is larger than 1 MiB", start: 0, end: 0)
        }
        try checkCodePoints()
        index = source.bomLength
        try checkVersionMarker()
        return try parseNodes(depth: 1, insideChildren: false)
    }

    func checkCodePoints() throws(KDLSyntaxError) {
        var offset = 0
        for scalar in text.unicodeScalars {
            let length = String(scalar).utf8.count
            if KDLCharacters.isDisallowed(scalar), !(scalar.value == 0xFEFF && offset == 0) {
                let code = String(scalar.value, radix: 16, uppercase: true)
                let padded = String(repeating: "0", count: max(0, 4 - code.count)) + code
                throw KDLSyntaxError(
                    message: "the code point U+\(padded) is not allowed in KDL; inside a quoted string write it as \\u{\(code)}",
                    start: offset,
                    end: offset + length
                )
            }
            offset += length
        }
    }

    func checkVersionMarker() throws(KDLSyntaxError) {
        guard source.hasPrefix("/-", at: index) else { return }
        let keyword = skipUnicodeSpaces(from: index + 2)
        guard source.hasPrefix("kdl-version", at: keyword) else { return }
        let afterKeyword = keyword + 11
        let digit = skipUnicodeSpaces(from: afterKeyword)
        guard digit > afterKeyword, source.byte(at: digit) == UInt8(ascii: "1") else { return }
        if let next = source.decoded(at: digit + 1), KDLCharacters.isIdentifierCharacter(next.scalar) {
            return
        }
        throw KDLSyntaxError(
            message: "this file is marked as KDL v1; ApolloShell reads KDL v2 only (booleans are #true and #false, null is #null, raw strings are #\"…\"#)",
            start: index,
            end: digit + 1
        )
    }

    func skipUnicodeSpaces(from offset: Int) -> Int {
        var cursor = offset
        while let decoded = source.decoded(at: cursor), KDLCharacters.isUnicodeSpace(decoded.scalar) {
            cursor += decoded.length
        }
        return cursor
    }

    mutating func parseNodes(depth: Int, insideChildren: Bool) throws(KDLSyntaxError) -> [KDLNode] {
        var nodes: [KDLNode] = []
        while true {
            try skipLineSpace()
            guard let byte = source.byte(at: index) else { return nodes }
            if byte == UInt8(ascii: "}") {
                if insideChildren { return nodes }
                throw KDLSyntaxError(message: "unexpected '}' without a matching '{'", start: index, end: index + 1)
            }
            guard depth <= KDLLimits.maxDepth else {
                throw KDLSyntaxError(message: "nodes are nested deeper than \(KDLLimits.maxDepth) levels", start: index, end: index + 1)
            }
            if let node = try parseNode(depth: depth, insideChildren: insideChildren) {
                nodes.append(node)
            }
        }
    }

    mutating func parseNode(depth: Int, insideChildren: Bool) throws(KDLSyntaxError) -> KDLNode? {
        var commented = false
        if source.hasPrefix("/-", at: index) {
            let slashdash = index
            index += 2
            try skipAfterSlashdash(slashdash)
            commented = true
        }
        let start = index
        let annotation = try parseTypeAnnotation()
        if annotation != nil {
            try skipNodeSpace()
        }
        let nameStart = index
        guard let name = try parseString(context: "node name") else {
            throw KDLSyntaxError(message: "expected a node name, found \(describe(at: index))", start: index, end: index + 1)
        }
        var node = KDLNode(name: name)
        node.annotation = annotation
        node.nameSpan = span(nameStart, index)
        var end = index
        try parseNodeBody(into: &node, end: &end, depth: depth)
        node.span = span(start, end)
        node.lineRange = KDLLineRange.range(in: source, start: start, end: end)
        try parseTerminator(insideChildren: insideChildren)
        return commented ? nil : node
    }

    mutating func parseNodeBody(into node: inout KDLNode, end: inout Int, depth: Int) throws(KDLSyntaxError) {
        var sawChildren = false
        var sawAnyChildren = false
        while true {
            let beforeSpace = index
            try skipNodeSpace()
            guard let byte = source.byte(at: index) else { return }
            if byte == UInt8(ascii: "}") || byte == UInt8(ascii: ";") || source.newlineLength(at: index) != nil || source.hasPrefix("//", at: index) {
                return
            }
            guard index > beforeSpace else {
                throw KDLSyntaxError(message: "expected whitespace before \(describe(at: index))", start: index, end: index + 1)
            }
            if source.hasPrefix("/-", at: index) {
                let slashdash = index
                index += 2
                try skipAfterSlashdash(slashdash)
                if source.byte(at: index) == UInt8(ascii: "{") {
                    _ = try parseChildren(depth: depth)
                    sawAnyChildren = true
                } else {
                    guard !sawAnyChildren else {
                        throw KDLSyntaxError(message: "arguments and properties must come before the children block", start: slashdash, end: slashdash + 2)
                    }
                    _ = try parseEntry()
                }
                end = index
                continue
            }
            if byte == UInt8(ascii: "{") {
                guard !sawChildren else {
                    throw KDLSyntaxError(message: "a node can have only one children block", start: index, end: index + 1)
                }
                let open = index
                node.children = try parseChildren(depth: depth)
                node.childrenBlock = open..<index
                sawChildren = true
                sawAnyChildren = true
                end = index
                continue
            }
            guard !sawAnyChildren else {
                throw KDLSyntaxError(message: "arguments and properties must come before the children block", start: index, end: index + 1)
            }
            switch try parseEntry() {
            case .argument(let value):
                node.arguments.append(value)
            case .property(let property):
                node.properties.append(property)
            }
            end = index
        }
    }

    mutating func parseTerminator(insideChildren: Bool) throws(KDLSyntaxError) {
        guard let byte = source.byte(at: index) else { return }
        if byte == UInt8(ascii: ";") {
            index += 1
            return
        }
        if let length = source.newlineLength(at: index) {
            index += length
            return
        }
        if source.hasPrefix("//", at: index) {
            skipSingleLineComment()
            if let length = source.newlineLength(at: index) {
                index += length
            }
            return
        }
        if byte == UInt8(ascii: "}"), insideChildren {
            return
        }
        throw KDLSyntaxError(message: "unexpected \(describe(at: index)) after the node", start: index, end: index + 1)
    }

    mutating func parseChildren(depth: Int) throws(KDLSyntaxError) -> [KDLNode] {
        let open = index
        index += 1
        let children = try parseNodes(depth: depth + 1, insideChildren: true)
        guard source.byte(at: index) == UInt8(ascii: "}") else {
            throw KDLSyntaxError(message: "this '{' is never closed", start: open, end: open + 1)
        }
        index += 1
        return children
    }

    mutating func skipAfterSlashdash(_ slashdash: Int) throws(KDLSyntaxError) {
        try skipLineSpace()
        if source.hasPrefix("/-", at: index) {
            throw KDLSyntaxError(message: "'/-' cannot comment out another '/-'", start: index, end: index + 2)
        }
        let next = source.byte(at: index)
        if next == nil || next == UInt8(ascii: "}") || next == UInt8(ascii: ";") {
            throw KDLSyntaxError(message: "'/-' must be followed by the node, entry or children block it comments out", start: slashdash, end: slashdash + 2)
        }
    }

    mutating func parseEntry() throws(KDLSyntaxError) -> Entry {
        let start = index
        if let key = try parseKeyCandidate() {
            try skipNodeSpace()
            if source.byte(at: index) == UInt8(ascii: "=") {
                index += 1
                try skipNodeSpace()
                let value = try parseValue()
                return .property(KDLProperty(name: key, value: value, span: span(start, index)))
            }
            index = start
        }
        return .argument(try parseValue())
    }

    mutating func parseKeyCandidate() throws(KDLSyntaxError) -> String? {
        if let quoted = try parseQuotedOrRaw() {
            return quoted
        }
        let start = index
        guard let decoded = source.decoded(at: index), KDLCharacters.isIdentifierCharacter(decoded.scalar) else {
            return nil
        }
        let word = scanIdentifierRun()
        if KDLCharacters.classify(word) == .identifier {
            return word
        }
        index = start
        return nil
    }

    mutating func parseValue() throws(KDLSyntaxError) -> KDLValue {
        let start = index
        let annotation = try parseTypeAnnotation()
        if annotation != nil {
            try skipNodeSpace()
        }
        let scalar: KDLScalar
        if let quoted = try parseQuotedOrRaw() {
            scalar = .string(quoted)
        } else if source.byte(at: index) == UInt8(ascii: "#") {
            scalar = try parseKeyword()
        } else if let decoded = source.decoded(at: index), KDLCharacters.isIdentifierCharacter(decoded.scalar) {
            scalar = try parseBareValue()
        } else {
            throw KDLSyntaxError(message: "expected a value, found \(describe(at: index))", start: index, end: index + 1)
        }
        return KDLValue(scalar, annotation: annotation, span: span(start, index))
    }

    mutating func parseKeyword() throws(KDLSyntaxError) -> KDLScalar {
        let start = index
        index += 1
        let word = scanIdentifierRun()
        switch word {
        case "true":
            return .bool(true)
        case "false":
            return .bool(false)
        case "null":
            return .null
        case "inf":
            return .number(.infinity, raw: "#inf")
        case "-inf":
            return .number(-.infinity, raw: "#-inf")
        case "nan":
            return .number(.nan, raw: "#nan")
        default:
            throw KDLSyntaxError(message: "unknown keyword '#\(word)'; KDL knows #true, #false, #null, #inf, #-inf and #nan", start: start, end: index)
        }
    }

    mutating func parseBareValue() throws(KDLSyntaxError) -> KDLScalar {
        let start = index
        let word = scanIdentifierRun()
        switch KDLCharacters.classify(word) {
        case .identifier:
            return .string(word)
        case .number:
            guard let value = KDLNumberLiteral.value(of: word) else {
                throw KDLSyntaxError(message: "'\(word)' is not a valid number", start: start, end: index)
            }
            return .number(value, raw: word)
        case .invalid(let message):
            throw KDLSyntaxError(message: message, start: start, end: index)
        }
    }

    mutating func parseTypeAnnotation() throws(KDLSyntaxError) -> String? {
        guard source.byte(at: index) == UInt8(ascii: "(") else { return nil }
        let open = index
        index += 1
        try skipNodeSpace()
        guard let name = try parseString(context: "type annotation") else {
            throw KDLSyntaxError(message: "a type annotation needs a name inside the parentheses", start: open, end: index + 1)
        }
        try skipNodeSpace()
        guard source.byte(at: index) == UInt8(ascii: ")") else {
            throw KDLSyntaxError(message: "expected ')' to close the type annotation, found \(describe(at: index))", start: index, end: index + 1)
        }
        index += 1
        return name
    }

    mutating func parseString(context: String) throws(KDLSyntaxError) -> String? {
        if let quoted = try parseQuotedOrRaw() {
            return quoted
        }
        guard let decoded = source.decoded(at: index), KDLCharacters.isIdentifierCharacter(decoded.scalar) else {
            return nil
        }
        let start = index
        let word = scanIdentifierRun()
        switch KDLCharacters.classify(word) {
        case .identifier:
            return word
        case .number:
            throw KDLSyntaxError(message: "'\(word)' looks like a number and cannot be a \(context); write it as \"\(word)\"", start: start, end: index)
        case .invalid(let message):
            throw KDLSyntaxError(message: message, start: start, end: index)
        }
    }

    mutating func parseQuotedOrRaw() throws(KDLSyntaxError) -> String? {
        if source.byte(at: index) == UInt8(ascii: "\"") {
            var scanner = KDLStringScanner(source: source, index: index)
            let value = try scanner.scanQuoted()
            index = scanner.index
            return value
        }
        if KDLStringScanner.isRawStart(source, at: index) {
            var scanner = KDLStringScanner(source: source, index: index)
            let value = try scanner.scanRaw()
            index = scanner.index
            return value
        }
        return nil
    }

    mutating func scanIdentifierRun() -> String {
        let start = index
        while let decoded = source.decoded(at: index), KDLCharacters.isIdentifierCharacter(decoded.scalar) {
            index += decoded.length
        }
        return source.string(from: start, to: index)
    }

    mutating func skipLineSpace() throws(KDLSyntaxError) {
        while index < source.count {
            if try skipNodeSpaceOnce() {
                continue
            }
            if let length = source.newlineLength(at: index) {
                index += length
                continue
            }
            if source.hasPrefix("//", at: index) {
                skipSingleLineComment()
                continue
            }
            return
        }
    }

    mutating func skipNodeSpace() throws(KDLSyntaxError) {
        while try skipNodeSpaceOnce() {}
    }

    mutating func skipNodeSpaceOnce() throws(KDLSyntaxError) -> Bool {
        if let decoded = source.decoded(at: index), KDLCharacters.isUnicodeSpace(decoded.scalar) {
            index += decoded.length
            return true
        }
        if source.hasPrefix("/*", at: index) {
            try skipBlockComment()
            return true
        }
        if source.byte(at: index) == UInt8(ascii: "\\") {
            try skipEscline()
            return true
        }
        return false
    }

    mutating func skipSingleLineComment() {
        while let decoded = source.decoded(at: index), !KDLCharacters.isNewline(decoded.scalar) {
            index += decoded.length
        }
    }

    mutating func skipBlockComment() throws(KDLSyntaxError) {
        let start = index
        index += 2
        var depth = 1
        while depth > 0 {
            guard index < source.count else {
                throw KDLSyntaxError(message: "this block comment is never closed", start: start, end: start + 2)
            }
            if source.hasPrefix("/*", at: index) {
                depth += 1
                index += 2
            } else if source.hasPrefix("*/", at: index) {
                depth -= 1
                index += 2
            } else {
                index += 1
            }
        }
    }

    mutating func skipEscline() throws(KDLSyntaxError) {
        let start = index
        index += 1
        while true {
            if let decoded = source.decoded(at: index), KDLCharacters.isUnicodeSpace(decoded.scalar) {
                index += decoded.length
            } else if source.hasPrefix("/*", at: index) {
                try skipBlockComment()
            } else {
                break
            }
        }
        if source.hasPrefix("//", at: index) {
            skipSingleLineComment()
        }
        guard index < source.count else { return }
        guard let length = source.newlineLength(at: index) else {
            throw KDLSyntaxError(message: "a line continuation '\\' must be followed by a line break", start: start, end: start + 1)
        }
        index += length
    }

    func describe(at offset: Int) -> String {
        guard let decoded = source.decoded(at: offset) else { return "the end of the file" }
        if KDLCharacters.isNewline(decoded.scalar) { return "a line break" }
        return "'\(Character(decoded.scalar))'"
    }

    func span(_ start: Int, _ end: Int) -> SourceSpan {
        SourceSpan(
            file: file,
            start: SourcePosition(offset: start, line: 0, column: 0),
            end: SourcePosition(offset: end, line: 0, column: 0)
        )
    }

    func resolvePositions(_ nodes: [KDLNode]) -> [KDLNode] {
        var offsets: [Int] = []
        for node in nodes {
            collectOffsets(node, into: &offsets)
        }
        let table = SourceLocator(text).positions(atByteOffsets: offsets)
        return nodes.map { resolved($0, table) }
    }

    func collectOffsets(_ node: KDLNode, into offsets: inout [Int]) {
        offsets += [node.span.start.offset, node.span.end.offset, node.nameSpan.start.offset, node.nameSpan.end.offset]
        for value in node.arguments {
            offsets += [value.span.start.offset, value.span.end.offset]
        }
        for property in node.properties {
            offsets += [property.span.start.offset, property.span.end.offset, property.value.span.start.offset, property.value.span.end.offset]
        }
        for child in node.children ?? [] {
            collectOffsets(child, into: &offsets)
        }
    }

    func resolved(_ node: KDLNode, _ table: [Int: SourcePosition]) -> KDLNode {
        var copy = node
        copy.span = resolvedSpan(node.span, table)
        copy.nameSpan = resolvedSpan(node.nameSpan, table)
        copy.arguments = node.arguments.map { argument in
            var value = argument
            value.span = resolvedSpan(argument.span, table)
            return value
        }
        copy.properties = node.properties.map { original in
            var property = original
            property.span = resolvedSpan(original.span, table)
            property.value.span = resolvedSpan(original.value.span, table)
            return property
        }
        copy.children = node.children?.map { resolved($0, table) }
        return copy
    }

    func resolvedSpan(_ span: SourceSpan, _ table: [Int: SourcePosition]) -> SourceSpan {
        SourceSpan(file: span.file, start: table[span.start.offset] ?? span.start, end: table[span.end.offset] ?? span.end)
    }
}
