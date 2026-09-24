import Foundation
import Testing
@testable import ApolloKDL

@Suite("KDL-Testfälle von kdl-org 2.0.0")
struct KDLConformanceTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/kdl-org/test_cases")

    static let inputNames: [String] = {
        let folder = root.appendingPathComponent("input")
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "kdl" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }()

    static func read(_ relativePath: String) throws -> String {
        String(decoding: try Data(contentsOf: root.appendingPathComponent(relativePath)), as: UTF8.self)
    }

    static func normalized(_ node: KDLNode) -> KDLNode {
        var copy = node
        var seen = Set<String>()
        var kept: [KDLProperty] = []
        for property in node.properties.reversed() where seen.insert(property.name).inserted {
            kept.append(property)
        }
        copy.properties = kept.sorted { $0.name < $1.name }
        if let children = node.children, !children.isEmpty {
            copy.children = children.map(normalized)
        } else {
            copy.children = nil
        }
        return copy
    }

    @Test("Fixture ist vollständig: 319 Eingaben, 232 Erwartungen")
    func fixtureIsComplete() throws {
        #expect(Self.inputNames.count == 319)
        let expected = try FileManager.default
            .contentsOfDirectory(atPath: Self.root.appendingPathComponent("expected_kdl").path)
            .filter { $0.hasSuffix(".kdl") }
        #expect(expected.count == 232)
    }

    @Test("Testfall wird wie erwartet gelesen oder abgelehnt", arguments: KDLConformanceTests.inputNames)
    func testCase(name: String) throws {
        let input = try Self.read("input/\(name).kdl")
        let expectedPath = Self.root.appendingPathComponent("expected_kdl/\(name).kdl").path
        let hasExpectation = FileManager.default.fileExists(atPath: expectedPath)
        #expect(hasExpectation != name.hasSuffix("_fail"))
        if hasExpectation {
            let parsed = try KDLDocument.parse(input, file: name)
            let expected = try KDLDocument.parse(try Self.read("expected_kdl/\(name).kdl"), file: name)
            let lhs = parsed.nodes.map(Self.normalized)
            let rhs = expected.nodes.map(Self.normalized)
            #expect(KDLNode.areEquivalent(lhs, rhs), "\(name): \(lhs) ist nicht \(rhs)")
        } else {
            #expect(throws: KDLParseError.self, "\(name) muss abgelehnt werden") {
                try KDLDocument.parse(input, file: name)
            }
        }
    }
}
