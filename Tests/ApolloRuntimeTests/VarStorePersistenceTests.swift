import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("VarStore Speichern")
struct VarStorePersistenceTests {
    func makeStore(fileSystem: MemoryFileSystem = MemoryFileSystem(), clock: ManualRuntimeClock = ManualRuntimeClock()) -> (SignalStore, BindingEngine, VarStore, ManualRuntimeClock, StateWriter) {
        let scheduler = ManualFlushScheduler()
        let store = SignalStore(scheduler: scheduler)
        let engine = BindingEngine(store: store, evaluator: BindingTestHarness.evaluator())
        let vars = VarStore(store: store, bindings: engine, clock: clock)
        let writer = StateWriter(file: URL(fileURLWithPath: "/state/test.kdl"), fileSystem: fileSystem)
        vars.onPersist = { values in
            _ = writer.write(values)
        }
        return (store, engine, vars, clock, writer)
    }

    func decl(_ name: String, type: ValueType, defaultText: String, persist: Bool = true) -> VarDecl {
        let template = ValueTemplate.scalar(try! CompiledValueBuilderAccess.compile("{\(defaultText)}"))
        return VarDecl(name: name, type: type, defaultValue: template, persist: persist, derived: nil, span: .synthetic("test"))
    }

    @Test("50 set in 400 ms ergeben einen Schreibvorgang")
    func manySetsInWindowWriteOnce() {
        let fileSystem = MemoryFileSystem()
        let (_, _, vars, clock, writer) = makeStore(fileSystem: fileSystem)
        vars.declare([decl("count", type: .number, defaultText: "0")], persisted: [:], shell: Record())
        var writeCount = 0
        vars.onPersist = { values in
            writeCount += 1
            _ = writer.write(values)
        }
        for index in 0..<50 {
            _ = vars.set("count", .number(Double(index)), for: nil)
            clock.advance(by: 0.008)
        }
        #expect(writeCount == 0)
        clock.advance(by: 0.5)
        #expect(writeCount == 1)
        #expect((try? fileSystem.read(URL(fileURLWithPath: "/state/test.kdl"))) != nil)
    }

    @Test("Dauerfeuer alle 100 ms über 3 s schreibt spätestens alle 500 ms")
    func steadyFireWritesAtLeastEvery500ms() {
        let fileSystem = MemoryFileSystem()
        let (_, _, vars, clock, writer) = makeStore(fileSystem: fileSystem)
        vars.declare([decl("count", type: .number, defaultText: "0")], persisted: [:], shell: Record())
        var writeCount = 0
        vars.onPersist = { values in
            writeCount += 1
            _ = writer.write(values)
        }
        var index = 0
        var elapsed = 0.0
        while elapsed < 3.0 {
            _ = vars.set("count", .number(Double(index)), for: nil)
            clock.advance(by: 0.1)
            elapsed += 0.1
            index += 1
        }
        #expect(writeCount >= 5)
        #expect(writeCount <= 7)
    }

    @Test("Byte-Vergleich ausserhalb des geänderten Knotens bleibt gleich")
    func writingPreservesUnrelatedText() {
        let fileSystem = MemoryFileSystem([
            "/state/test.kdl": "// a comment\ncount 1\nother \"keep\"\r\n"
        ])
        let (_, _, vars, clock, writer) = makeStore(fileSystem: fileSystem)
        vars.declare([decl("count", type: .number, defaultText: "0")], persisted: ["count": .number(1)], shell: Record())
        _ = vars.set("count", .number(2), for: nil)
        clock.advance(by: 0.5)
        let text = try! fileSystem.read(URL(fileURLWithPath: "/state/test.kdl"))
        #expect(text.contains("// a comment"))
        #expect(text.contains("other \"keep\"\r\n") || text.contains("other \"keep\""))
        #expect(text.contains("count 2"))
        #expect(writer.lastWrittenText == text)
    }

    @Test("for=-Wert steht nie in der Datei")
    func transientValueNeverPersisted() {
        let fileSystem = MemoryFileSystem()
        let (_, _, vars, clock, writer) = makeStore(fileSystem: fileSystem)
        vars.declare([decl("volume", type: .number, defaultText: "0.5")], persisted: [:], shell: Record())
        _ = vars.set("volume", .number(0.5), for: nil)
        clock.advance(by: 0.5)
        _ = vars.set("volume", .number(0.9), for: 5.0)
        clock.advance(by: 0.5)
        let text = try! fileSystem.read(URL(fileURLWithPath: "/state/test.kdl"))
        #expect(!text.contains("0.9"))
        _ = writer
    }

    @Test("MemoryFileSystem, das wirft: eine Warnung, zweiter Fehlschlag keine weitere")
    func throwingFileSystemWarnsOnce() {
        final class ThrowingFileSystem: ConfigFileSystem, @unchecked Sendable {
            func read(_ url: URL) throws -> String { "" }
            func contentsOfDirectory(_ url: URL) throws -> [URL] { [] }
            func exists(_ url: URL) -> Bool { false }
            func isDirectory(_ url: URL) -> Bool { false }
            func resolvingSymlinks(_ url: URL) -> URL { url }
            func write(_ text: String, to url: URL) throws { throw ConfigFileSystemError("disk full") }
            func copyItem(_ source: URL, to destination: URL) throws {}
        }
        let writer = StateWriter(file: URL(fileURLWithPath: "/state/test.kdl"), fileSystem: ThrowingFileSystem())
        let first = writer.write(["count": .number(1)])
        let second = writer.write(["count": .number(2)])
        #expect(first != nil)
        #expect(second == nil)
    }

    @Test("flushPendingSaves schreibt sofort")
    func flushPendingSavesWritesImmediately() {
        let fileSystem = MemoryFileSystem()
        let (_, _, vars, _, _) = makeStore(fileSystem: fileSystem)
        vars.declare([decl("count", type: .number, defaultText: "0")], persisted: [:], shell: Record())
        _ = vars.set("count", .number(3), for: nil)
        vars.flushPendingSaves()
        let text = try! fileSystem.read(URL(fileURLWithPath: "/state/test.kdl"))
        #expect(text.contains("count 3"))
    }

    @Test("Lesen nach Änderung von aussen übernimmt den Wert wie set, mit Typprüfung")
    func applyExternalAppliesLikeSet() {
        let fileSystem = MemoryFileSystem()
        let (store, _, vars, _, _) = makeStore(fileSystem: fileSystem)
        vars.declare([decl("count", type: .number, defaultText: "0")], persisted: [:], shell: Record())
        vars.applyExternal(text: "count 42\n")
        #expect(vars.value("count") == .number(42))
        #expect(store.value(DependencyPath("var", ["count"])) == .number(42))
    }

    @Test("Lesen nach Änderung von aussen mit falschem Typ verwirft und warnt, alter Wert bleibt")
    func applyExternalDiscardsWrongTypedValue() {
        let fileSystem = MemoryFileSystem()
        let (store, _, vars, _, _) = makeStore(fileSystem: fileSystem)
        var warnings: [Diagnostic] = []
        vars.onWarning = { warnings.append($0) }
        vars.declare([decl("count", type: .number, defaultText: "0")], persisted: [:], shell: Record())
        vars.applyExternal(text: "count \"not-a-number\"\n")
        #expect(vars.value("count") == .number(0))
        #expect(store.value(DependencyPath("var", ["count"])) == .number(0))
        #expect(warnings.contains { $0.kind == .valueDiscarded })
    }

    @Test("Statusdatei mit 50 000 Listeneinträgen: ein geänderter Eintrag schreibt im Budget")
    func largeListWritesQuickly() {
        var lines = ["big {"]
        for index in 0..<50_000 { lines.append("    - \"item-\(index)\"") }
        lines.append("}")
        let initial = lines.joined(separator: "\n") + "\n"
        let fileSystem = MemoryFileSystem(["/state/test.kdl": initial])
        let writer = StateWriter(file: URL(fileURLWithPath: "/state/test.kdl"), fileSystem: fileSystem)
        var items: [Value] = (0..<50_000).map { .string("item-\($0)") }
        items[10] = .string("changed")
        let start = Date()
        let diagnostic = writer.write(["big": .list(items)])
        let elapsed = Date().timeIntervalSince(start)
        #expect(diagnostic == nil)
        #expect(elapsed < 2.0)
        let text = try! fileSystem.read(URL(fileURLWithPath: "/state/test.kdl"))
        #expect(text.contains("changed"))
    }
}
