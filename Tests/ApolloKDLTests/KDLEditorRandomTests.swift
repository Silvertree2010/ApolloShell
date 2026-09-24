import Foundation
import Testing
@testable import ApolloKDL

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

enum EditOperation {
    case replace(KDLNodePath, KDLNode)
    case insertAfter(KDLNodePath, KDLNode)
    case insertInto(KDLNodePath?, Int, KDLNode)
    case remove(KDLNodePath)
}

struct RandomKDLFactory {
    var rng: SplitMix64
    var newline = "\n"
    var unit = "    "

    static let nodeNames = [
        "node", "gr\u{FC}\u{DF}e", "emoji-\u{1F389}", "with space", "0digit", "true", "x", "\u{65E5}\u{672C}", "",
    ]
    static let propertyNames = ["size", "gr\u{FC}\u{DF}e", "a b", "id"]
    static let strings = [
        "", "plain", "Gr\u{FC}\u{DF}e \u{1F44B}", "tab\there", "quote \" and \\ backslash", "line\nbreak",
        "\u{1F1E8}\u{1F1ED}\u{1F39B}\u{FE0F}\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}",
        String(repeating: "lang ", count: 300),
    ]
    static let numbers: [(Double, String)] = [(1, "1"), (-2.5, "-2.5"), (255, "0xff"), (1000, "1_000"), (0.001, "1e-3")]

    mutating func chance(_ percent: Int) -> Bool {
        Int.random(in: 0..<100, using: &rng) < percent
    }

    mutating func amount(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &rng)
    }

    mutating func pick<Element>(_ items: [Element]) -> Element {
        items[Int.random(in: 0..<items.count, using: &rng)]
    }

    mutating func value() -> KDLValue {
        let annotation: String? = chance(10) ? "typ" : nil
        switch amount(0...4) {
        case 0, 1:
            return KDLValue(.string(pick(Self.strings)), annotation: annotation)
        case 2:
            let number = pick(Self.numbers)
            return KDLValue(.number(number.0, raw: number.1), annotation: annotation)
        case 3:
            return KDLValue(.bool(chance(50)), annotation: annotation)
        default:
            return KDLValue(.null, annotation: annotation)
        }
    }

    mutating func node(depth: Int) -> KDLNode {
        var result = KDLNode(name: pick(Self.nodeNames))
        if chance(10) {
            result.annotation = "t"
        }
        for _ in 0..<amount(0...3) {
            result.arguments.append(value())
        }
        for _ in 0..<amount(0...2) {
            result.properties.append(KDLProperty(name: pick(Self.propertyNames), value: value()))
        }
        if depth < 3, chance(35) {
            var children: [KDLNode] = []
            for _ in 0..<amount(0...3) {
                children.append(node(depth: depth + 1))
            }
            result.children = children
        }
        return result
    }

    mutating func document() -> (text: String, nodes: [KDLNode]) {
        newline = chance(30) ? "\r\n" : "\n"
        unit = chance(30) ? "\t" : (chance(50) ? "  " : "    ")
        var nodes: [KDLNode] = []
        for _ in 0..<amount(0...5) {
            nodes.append(node(depth: 0))
        }
        var text = chance(5) ? "\u{FEFF}" : ""
        if chance(20) {
            text += "// kopf" + newline
        }
        text += render(nodes, indent: "")
        if chance(20), text.hasSuffix(newline) {
            text.removeLast()
        }
        return (text, nodes)
    }

    mutating func render(_ nodes: [KDLNode], indent: String) -> String {
        var output = ""
        var index = 0
        while index < nodes.count {
            if chance(15) {
                output += indent + "// kommentar \u{1F4AC}" + newline
            }
            if chance(10) {
                output += newline
            }
            if chance(10) {
                output += indent + "/- weg 1 { x }" + newline
            }
            output += indent + line(nodes[index], indent: indent, inline: false)
            if index + 1 < nodes.count, chance(15) {
                output += "; " + line(nodes[index + 1], indent: indent, inline: false)
                index += 1
            }
            if chance(15) {
                output += " // notiz"
            } else if chance(10) {
                output += ";"
            }
            output += newline
            index += 1
        }
        return output
    }

    mutating func line(_ node: KDLNode, indent: String, inline: Bool) -> String {
        var output = ""
        if let annotation = node.annotation {
            output += "(" + annotation + ")"
        }
        output += Self.name(node.name)
        for argument in node.arguments {
            output += separator(indent: indent, inline: inline) + value(argument, indent: indent, inline: inline)
        }
        for property in node.properties {
            output += separator(indent: indent, inline: inline) + Self.name(property.name) + "=" + value(property.value, indent: indent, inline: inline)
        }
        guard let children = node.children else { return output }
        if children.isEmpty {
            if inline {
                return output + " {}"
            }
            return output + (chance(50) ? " {}" : " {" + newline + indent + "}")
        }
        var compact = inline
        if !compact {
            compact = chance(25)
        }
        if compact {
            var parts: [String] = []
            for child in children {
                parts.append(line(child, indent: indent, inline: true))
            }
            return output + " { " + parts.joined(separator: "; ") + " }"
        }
        return output + " {" + newline + render(children, indent: indent + unit) + indent + "}"
    }

    mutating func separator(indent: String, inline: Bool) -> String {
        if inline {
            return " "
        }
        if chance(8) {
            return " \\" + newline + indent + unit
        }
        return chance(10) ? "  " : " "
    }

    mutating func value(_ value: KDLValue, indent: String, inline: Bool) -> String {
        var output = ""
        if let annotation = value.annotation {
            output += "(" + annotation + ")"
        }
        switch value.scalar {
        case .string(let text):
            output += string(text, indent: indent, inline: inline)
        case .number(_, let raw):
            output += raw
        case .bool(let flag):
            output += flag ? "#true" : "#false"
        case .null:
            output += "#null"
        }
        return output
    }

    mutating func string(_ text: String, indent: String, inline: Bool) -> String {
        if !inline, text.contains("\n"), chance(50) {
            let inner = indent + unit
            var output = "#\"\"\"" + newline
            for part in text.split(separator: "\n", omittingEmptySubsequences: false) {
                output += (part.isEmpty ? "" : inner + part) + newline
            }
            return output + inner + "\"\"\"#"
        }
        if !text.contains("\n"), !text.contains("\"#"), chance(30) {
            return "#\"" + text + "\"#"
        }
        return Self.quoted(text)
    }

    static func quoted(_ text: String) -> String {
        var output = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"":
                output += "\\\""
            case "\\":
                output += "\\\\"
            case "\n":
                output += "\\n"
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        return output + "\""
    }

    static func name(_ text: String) -> String {
        KDLCharacters.isValidBareIdentifier(text) ? text : quoted(text)
    }

    static func paths(_ nodes: [KDLNode], prefix: KDLNodePath = []) -> [KDLNodePath] {
        var result: [KDLNodePath] = []
        for (index, node) in nodes.enumerated() {
            let path = prefix + [index]
            result.append(path)
            result += paths(node.children ?? [], prefix: path)
        }
        return result
    }

    static func node(at path: KDLNodePath, in nodes: [KDLNode]) -> KDLNode {
        var current = nodes[path[0]]
        for index in path.dropFirst() {
            current = (current.children ?? [])[index]
        }
        return current
    }

    mutating func operation(on model: [KDLNode]) -> EditOperation {
        let all = Self.paths(model)
        let fresh = node(depth: 2)
        guard !all.isEmpty else {
            return .insertInto(nil, 0, fresh)
        }
        let path = pick(all)
        switch amount(0...3) {
        case 0:
            return .replace(path, fresh)
        case 1:
            return .insertAfter(path, fresh)
        case 2:
            if chance(30) {
                return .insertInto(nil, amount(0...model.count), fresh)
            }
            let parent = Self.node(at: path, in: model)
            return .insertInto(path, amount(0...(parent.children?.count ?? 0)), fresh)
        default:
            return .remove(path)
        }
    }
}

@Suite("KDL-Editor: Zufallstest")
struct KDLEditorRandomTests {
    static func mutate(_ nodes: inout [KDLNode], _ path: ArraySlice<Int>, _ body: (inout [KDLNode], Int) -> Void) {
        guard let first = path.first else { return }
        if path.count == 1 {
            body(&nodes, first)
            return
        }
        var children = nodes[first].children ?? []
        mutate(&children, path.dropFirst(), body)
        nodes[first].children = children
    }

    static func apply(_ operation: EditOperation, to nodes: inout [KDLNode]) {
        switch operation {
        case .replace(let path, let node):
            mutate(&nodes, path[...]) { siblings, index in siblings[index] = node }
        case .insertAfter(let path, let node):
            mutate(&nodes, path[...]) { siblings, index in siblings.insert(node, at: index + 1) }
        case .insertInto(let parent, let position, let node):
            if let parent {
                mutate(&nodes, parent[...]) { siblings, index in
                    var children = siblings[index].children ?? []
                    children.insert(node, at: position)
                    siblings[index].children = children
                }
            } else {
                nodes.insert(node, at: position)
            }
        case .remove(let path):
            mutate(&nodes, path[...]) { siblings, index in siblings.remove(at: index) }
        }
    }

    static func perform(_ operation: EditOperation, on editor: inout KDLEditor) throws {
        switch operation {
        case .replace(let path, let node):
            try editor.replace(at: path, with: node)
        case .insertAfter(let path, let node):
            try editor.insert(node, after: path)
        case .insertInto(let parent, let position, let node):
            try editor.insert(node, intoChildrenOf: parent, at: position)
        case .remove(let path):
            try editor.remove(at: path)
        }
    }

    static func expectedWindow(for operation: EditOperation, in nodes: [KDLNode], textLength: Int) -> Range<Int> {
        switch operation {
        case .replace(let path, _):
            let old = RandomKDLFactory.node(at: path, in: nodes)
            return old.span.start.offset..<old.span.end.offset
        case .remove(let path):
            return RandomKDLFactory.node(at: path, in: nodes).lineRange
        case .insertAfter(let path, _):
            return RandomKDLFactory.node(at: path, in: nodes).lineRange
        case .insertInto(let parent, let index, _):
            let siblings: [KDLNode]
            if let parent {
                siblings = RandomKDLFactory.node(at: parent, in: nodes).children ?? []
            } else {
                siblings = nodes
            }
            if index > 0 {
                return RandomKDLFactory.node(at: (parent ?? []) + [index - 1], in: nodes).lineRange
            }
            if let first = siblings.first {
                return first.lineRange
            }
            if let parent {
                return RandomKDLFactory.node(at: parent, in: nodes).lineRange
            }
            return textLength..<textLength
        }
    }

    static func unchangedOutside(before: String, after: String, window: Range<Int>) -> Bool {
        let beforeBytes = Array(before.utf8)
        let afterBytes = Array(after.utf8)
        guard window.lowerBound >= 0, window.upperBound <= beforeBytes.count else { return false }
        let prefixLength = window.lowerBound
        let suffixLength = beforeBytes.count - window.upperBound
        guard afterBytes.count >= prefixLength, afterBytes.count >= suffixLength else { return false }
        let prefixMatches = afterBytes.prefix(prefixLength).elementsEqual(beforeBytes.prefix(prefixLength))
        let suffixMatches = afterBytes.suffix(suffixLength).elementsEqual(beforeBytes.suffix(suffixLength))
        return prefixMatches && suffixMatches
    }

    static func run(sequences: Range<Int>, operations: Int, sabotage: Bool) -> [String] {
        var failures: [String] = []
        for sequence in sequences {
            var factory = RandomKDLFactory(rng: SplitMix64(state: UInt64(sequence) &* 0x2545_F491_4F6C_DD1D &+ 1))
            let (text, nodes) = factory.document()
            let parsed: KDLDocument
            do {
                parsed = try KDLDocument.parse(text, file: "zufall.kdl")
            } catch {
                failures.append("Folge \(sequence): erzeugter Text parst nicht: \(error)\n\(text)")
                continue
            }
            guard KDLNode.areEquivalent(parsed.nodes, nodes) else {
                failures.append("Folge \(sequence): erzeugter Text entspricht nicht dem Modell\n\(text)")
                continue
            }
            var editor = KDLEditor(parsed)
            var model = nodes
            for step in 0..<operations {
                let sabotaged = sabotage && step == 0
                let operation = sabotaged ? EditOperation.insertInto(nil, 0, KDLNode(name: "sabotage")) : factory.operation(on: model)
                let before = editor.text
                let beforeNodes = editor.document.nodes
                do {
                    try perform(operation, on: &editor)
                } catch {
                    failures.append("Folge \(sequence), Schritt \(step): \(operation) scheitert: \(error)\n\(before)")
                    break
                }
                if !sabotaged {
                    apply(operation, to: &model)
                }
                let reparsed = try? KDLDocument.parse(editor.text, file: "zufall.kdl")
                guard let reparsed,
                      KDLNode.areEquivalent(reparsed.nodes, model),
                      KDLNode.areEquivalent(editor.document.nodes, model)
                else {
                    failures.append("Folge \(sequence), Schritt \(step): Ergebnis weicht vom Modell ab nach \(operation)\nvorher:\n\(before)\nnachher:\n\(editor.text)")
                    break
                }
                let window = expectedWindow(for: operation, in: beforeNodes, textLength: before.utf8.count)
                guard unchangedOutside(before: before, after: editor.text, window: window) else {
                    failures.append("Folge \(sequence), Schritt \(step): Bytes ausserhalb des Fensters \(window) geändert nach \(operation)\nvorher:\n\(before)\nnachher:\n\(editor.text)")
                    break
                }
            }
        }
        return failures
    }

    @Test("1000 zufällige Folgen enden in einer Datei, die parst und dem Modell entspricht, und Bytes ausserhalb bleiben gleich")
    func thousandSequences() {
        let failures = Self.run(sequences: 0..<1000, operations: 5, sabotage: false)
        #expect(failures.isEmpty, "\(failures.count) Fehler, die ersten:\n\(failures.prefix(3).joined(separator: "\n\n"))")
    }

    @Test("Messvorrichtung beweist sich: ein falsch geführtes Modell fällt in jeder Folge auf")
    func detectsWrongModel() {
        let failures = Self.run(sequences: 0..<20, operations: 1, sabotage: true)
        #expect(failures.count == 20)
        #expect(failures.allSatisfy { $0.contains("weicht vom Modell ab") || $0.contains("parst nicht") || $0.contains("entspricht nicht") })
    }

    @Test("Messvorrichtung beweist sich: ein Byte ausserhalb des erwarteten Fensters fällt auf, auch wenn das Modell stimmt")
    func detectsByteChangeOutsideExpectedWindow() throws {
        let text = "a 1\n\nb 2\nc 3\n"
        var editor = KDLEditor(try KDLDocument.parse(text, file: "zufall.kdl"))
        let nodes = editor.document.nodes
        let target = nodes[1]
        var expected = nodes
        expected.remove(at: 1)
        let sabotagedRange = (target.lineRange.lowerBound - 1)..<target.lineRange.upperBound
        try editor.commit(replacing: sabotagedRange, with: "", expected: expected)
        #expect(KDLNode.areEquivalent(editor.document.nodes, expected))
        #expect(!Self.unchangedOutside(before: text, after: editor.text, window: target.lineRange))
    }
}
