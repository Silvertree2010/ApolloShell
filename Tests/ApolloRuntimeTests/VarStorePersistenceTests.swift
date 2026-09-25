import Testing
import Foundation
import Synchronization
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("VarStore Speichern")
struct VarStorePersistenceTests {
    func makeStore(fileSystem: any ConfigFileSystem = MemoryFileSystem(), clock: ManualRuntimeClock = ManualRuntimeClock()) -> (SignalStore, BindingEngine, VarStore, ManualRuntimeClock, StateWriter) {
        let scheduler = ManualFlushScheduler()
        let store = SignalStore(scheduler: scheduler)
        let engine = BindingEngine(store: store, evaluator: BindingTestHarness.evaluator())
        let vars = VarStore(store: store, bindings: engine, clock: clock)
        let writer = StateWriter(file: URL(fileURLWithPath: "/state/test.kdl"), fileSystem: fileSystem)
        vars.connect(writer)
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
        vars.onPersist = { _ in writeCount += 1 }
        for index in 0..<50 {
            _ = vars.set("count", .number(Double(index)), for: nil)
            clock.advance(by: 0.008)
        }
        #expect(writeCount == 0)
        clock.advance(by: 0.5)
        #expect(writeCount == 1)
        writer.flushSync()
        #expect((try? fileSystem.read(URL(fileURLWithPath: "/state/test.kdl"))) == "count 49\n")
    }

    @Test("Dauerfeuer alle 100 ms über 3 s schreibt spätestens alle 500 ms")
    func steadyFireWritesAtLeastEvery500ms() {
        let fileSystem = MemoryFileSystem()
        let (_, _, vars, clock, writer) = makeStore(fileSystem: fileSystem)
        vars.declare([decl("count", type: .number, defaultText: "0")], persisted: [:], shell: Record())
        var writeCount = 0
        vars.onPersist = { _ in writeCount += 1 }
        _ = writer
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

    @Test("Byte-Vergleich ausserhalb des geänderten Knotens bleibt gleich, mit Kommentar, CRLF und Emoji")
    func writingPreservesUnrelatedText() {
        let url = URL(fileURLWithPath: "/state/test.kdl")
        let fileSystem = MemoryFileSystem([
            "/state/test.kdl": "// a comment 🦞\r\ncount 1\r\nlabel \"grüezi 👋🏽\"\r\nother \"keep\"\r\n"
        ])
        let (_, _, vars, clock, writer) = makeStore(fileSystem: fileSystem)
        vars.declare([
            decl("count", type: .number, defaultText: "0"),
            decl("label", type: .string, defaultText: "''")
        ], persisted: ["count": .number(1), "label": .string("grüezi 👋🏽")], shell: Record())
        _ = vars.set("count", .number(2), for: nil)
        clock.advance(by: 0.5)
        writer.flushSync()
        let first = try! fileSystem.read(url)
        #expect(Array(first.utf8) == Array("// a comment 🦞\r\ncount 2\r\nlabel \"grüezi 👋🏽\"\r\nother \"keep\"\r\n".utf8))
        #expect(writer.lastWrittenText == first)
        _ = vars.set("label", .string("🏔️ Chur"), for: nil)
        clock.advance(by: 0.5)
        writer.flushSync()
        let second = try! fileSystem.read(url)
        #expect(Array(second.utf8) == Array("// a comment 🦞\r\ncount 2\r\nlabel \"🏔️ Chur\"\r\nother \"keep\"\r\n".utf8))
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
        vars.flushPendingSaves()
        let text = try! fileSystem.read(URL(fileURLWithPath: "/state/test.kdl"))
        #expect(!text.contains("0.9"))
        #expect(writer.lastWrittenText == text)
    }

    @Test("Dateisystem, das beim Schreiben wirft: eine Warnung, zweiter Fehlschlag keine weitere, alte Datei unverändert")
    func throwingFileSystemWarnsOnceAndKeepsOldFile() {
        let original = "// keep me\ncount 1\n"
        let fileSystem = FailingWriteFileSystem(MemoryFileSystem(["/state/test.kdl": original]))
        let writer = StateWriter(file: URL(fileURLWithPath: "/state/test.kdl"), fileSystem: fileSystem)
        let warnings = Mutex<[Diagnostic]>([])
        writer.setWarningHandler { diagnostic in warnings.withLock { $0.append(diagnostic) } }
        writer.enqueue(["count": .number(1), "extra": .number(2)])
        writer.enqueue(["count": .number(3)])
        writer.flushSync()
        let received = warnings.withLock { $0 }
        #expect(received.map(\.message) == ["test.kdl could not be saved. The change only applies until the next restart."])
        #expect((try? fileSystem.read(URL(fileURLWithPath: "/state/test.kdl"))) == original)
    }

    @Test("Unlesbare Statusdatei: erste Änderung sichert sie als .unreadable und schreibt neu, spätere Änderungen landen weiter")
    func unreadableFileIsReplacedOnWrite() throws {
        let broken = "count 1\nname \"open\n"
        let fileSystem = MemoryFileSystem(["/state/test.kdl": broken])
        let writer = StateWriter(file: URL(fileURLWithPath: "/state/test.kdl"), fileSystem: fileSystem)
        let warnings = Mutex<[Diagnostic]>([])
        writer.setWarningHandler { diagnostic in warnings.withLock { $0.append(diagnostic) } }
        writer.enqueue(["count": .number(2)])
        writer.enqueue(["count": .number(3), "other": .bool(true)])
        writer.flushSync()
        #expect(try fileSystem.read(URL(fileURLWithPath: "/state/test.kdl.unreadable")) == broken)
        let text = try fileSystem.read(URL(fileURLWithPath: "/state/test.kdl"))
        #expect(VarStateFile.readAll(text, file: "test.kdl").0 == ["count": .number(3), "other": .bool(true)])
        #expect(warnings.withLock { $0 }.count == 1)
    }

    @Test("Zwei schnelle Schreibvorgänge landen in Reihenfolge und ausserhalb des Main Threads")
    func writesAreSerialAndOffMain() {
        let fileSystem = RecordingFileSystem(MemoryFileSystem(), slowFirstWrite: 0.05)
        let writer = StateWriter(file: URL(fileURLWithPath: "/state/test.kdl"), fileSystem: fileSystem)
        writer.enqueue(["count": .number(1)])
        writer.enqueue(["count": .number(2)])
        writer.flushSync()
        let writes = fileSystem.writes
        #expect(writes.map(\.text) == ["count 1\n", "count 2\n"])
        #expect(writes.allSatisfy { !$0.onMainThread })
        #expect((try? fileSystem.read(URL(fileURLWithPath: "/state/test.kdl"))) == "count 2\n")
    }

    @Test("flushPendingSaves beim Beenden schreibt synchron, auch mit Warteschlange")
    func flushPendingSavesIsSynchronousWithQueue() {
        let fileSystem = RecordingFileSystem(MemoryFileSystem(), slowFirstWrite: 0.05)
        let (_, _, vars, _, _) = makeStore(fileSystem: fileSystem)
        vars.declare([decl("count", type: .number, defaultText: "0")], persisted: [:], shell: Record())
        _ = vars.set("count", .number(3), for: nil)
        vars.flushPendingSaves()
        #expect((try? fileSystem.read(URL(fileURLWithPath: "/state/test.kdl"))) == "count 3\n")
    }

    @Test("Äussere Änderung während eines ausstehenden Schreibens gewinnt")
    func externalChangeWinsOverPendingWrite() {
        let url = URL(fileURLWithPath: "/state/test.kdl")
        let fileSystem = MemoryFileSystem(["/state/test.kdl": "count 1\nother 1\n"])
        let (_, _, vars, clock, writer) = makeStore(fileSystem: fileSystem)
        vars.declare([
            decl("count", type: .number, defaultText: "0"),
            decl("other", type: .number, defaultText: "0")
        ], persisted: ["count": .number(1), "other": .number(1)], shell: Record())
        _ = vars.set("count", .number(5), for: nil)
        _ = vars.set("other", .number(6), for: nil)
        try! fileSystem.write("count 9\nother 1\n", to: url)
        clock.advance(by: 0.5)
        writer.flushSync()
        #expect((try? fileSystem.read(url)) == "count 9\nother 6\n")
        vars.applyExternal(text: try! fileSystem.read(url))
        #expect(vars.value("count") == .number(9))
        #expect(vars.value("other") == .number(6))
        _ = vars.set("count", .number(11), for: nil)
        clock.advance(by: 0.5)
        writer.flushSync()
        #expect((try? fileSystem.read(url)) == "count 11\nother 6\n")
    }

    @Test("Äussere Änderung an einem anderen Namen lässt ungespeicherte Werte und for= in Ruhe")
    func externalChangeTouchesOnlyChangedNames() {
        let fileSystem = MemoryFileSystem(["/state/test.kdl": "count 1\nvolume 0.5\nother 1\n"])
        let (_, _, vars, clock, _) = makeStore(fileSystem: fileSystem)
        vars.declare([
            decl("count", type: .number, defaultText: "0"),
            decl("volume", type: .number, defaultText: "0.5"),
            decl("other", type: .number, defaultText: "0")
        ], persisted: ["count": .number(1), "volume": .number(0.5), "other": .number(1)], shell: Record())
        _ = vars.set("count", .number(5), for: nil)
        _ = vars.set("volume", .number(0.9), for: 5.0)
        vars.applyExternal(text: "count 1\nvolume 0.5\nother 2\n")
        #expect(vars.value("other") == .number(2))
        #expect(vars.value("count") == .number(5))
        #expect(vars.value("volume") == .number(0.9))
        clock.advance(by: 5)
        #expect(vars.value("volume") == .number(0.5))
    }

    @Test("Eigener Schreibvorgang kommt nicht als Änderung von aussen zurück")
    func ownWriteIsNoEcho() {
        let url = URL(fileURLWithPath: "/state/test.kdl")
        let fileSystem = MemoryFileSystem()
        let (_, _, vars, clock, writer) = makeStore(fileSystem: fileSystem)
        vars.declare([decl("count", type: .number, defaultText: "0")], persisted: [:], shell: Record())
        _ = vars.set("count", .number(2), for: nil)
        clock.advance(by: 0.5)
        writer.flushSync()
        let own = try! fileSystem.read(url)
        _ = vars.set("count", .number(3), for: nil)
        vars.applyExternal(text: own)
        #expect(vars.value("count") == .number(3))
    }

    @Test("Unlesbarer Wert von aussen wird verworfen und die Datei als .unreadable kopiert")
    func applyExternalPreservesUnreadableCopy() {
        let fileSystem = MemoryFileSystem(["/state/test.kdl": "count 1\n"])
        let (_, _, vars, _, writer) = makeStore(fileSystem: fileSystem)
        vars.declare([decl("count", type: .number, defaultText: "0")], persisted: ["count": .number(1)], shell: Record())
        let text = "count \"broken\"\n"
        vars.applyExternal(text: text)
        writer.flushSync()
        #expect(vars.value("count") == .number(1))
        #expect((try? fileSystem.read(URL(fileURLWithPath: "/state/test.kdl.unreadable"))) == text)
    }

    @Test("flushPendingSaves schreibt sofort")
    func flushPendingSavesWritesImmediately() {
        let fileSystem = MemoryFileSystem()
        let (_, _, vars, _, _) = makeStore(fileSystem: fileSystem)
        vars.declare([decl("count", type: .number, defaultText: "0")], persisted: [:], shell: Record())
        _ = vars.set("count", .number(3), for: nil)
        vars.flushPendingSaves()
        let text = try! fileSystem.read(URL(fileURLWithPath: "/state/test.kdl"))
        #expect(text == "count 3\n")
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

    @Test("Lesen von aussen prüft auch Aufzählungstypen")
    func applyExternalChecksEnumeration() {
        let (_, _, vars, _, _) = makeStore()
        var warnings: [Diagnostic] = []
        vars.onWarning = { warnings.append($0) }
        let template = ValueTemplate.scalar(try! CompiledValueBuilderAccess.compile("{'a'}"))
        vars.declare([VarDecl(name: "mode", type: .enumeration(["a", "b"]), defaultValue: template, persist: true, derived: nil, span: .synthetic("test"))], persisted: [:], shell: Record())
        vars.applyExternal(text: "mode \"zzz\"\n")
        #expect(vars.value("mode") == .string("a"))
        #expect(warnings.count == 1)
        vars.applyExternal(text: "mode \"b\"\n")
        #expect(vars.value("mode") == .string("b"))
    }

    @Test("Statusdatei mit 50 000 Listeneinträgen: ein geänderter Eintrag kostet linear, nicht quadratisch")
    func largeListWritesLinearly() {
        func writeCost(_ count: Int) -> Double {
            var lines = ["big {"]
            for index in 0..<count { lines.append("    - \"item-\(index)\"") }
            lines.append("}")
            let initial = lines.joined(separator: "\n") + "\n"
            let fileSystem = MemoryFileSystem(["/state/test.kdl": initial])
            let writer = StateWriter(file: URL(fileURLWithPath: "/state/test.kdl"), fileSystem: fileSystem)
            var items: [Value] = (0..<count).map { .string("item-\($0)") }
            items[10] = .string("changed")
            var diagnostic: Diagnostic?
            let cost = CPUTime.measure {
                diagnostic = writer.write(["big": .list(items)])
            }
            #expect(diagnostic == nil)
            let text = try! fileSystem.read(URL(fileURLWithPath: "/state/test.kdl"))
            #expect(text.contains("changed"))
            return cost
        }
        let small = (0..<3).map { _ in writeCost(5_000) }.min()!
        let large = writeCost(50_000)
        print("state-write cpu ms small=\(small) large=\(large) ratio=\(large / small)")
        #expect(large / small < 40)
    }
}

final class FailingWriteFileSystem: ConfigFileSystem, Sendable {
    private let base: MemoryFileSystem

    init(_ base: MemoryFileSystem) {
        self.base = base
    }

    func read(_ url: URL) throws -> String { try base.read(url) }
    func contentsOfDirectory(_ url: URL) throws -> [URL] { try base.contentsOfDirectory(url) }
    func exists(_ url: URL) -> Bool { base.exists(url) }
    func isDirectory(_ url: URL) -> Bool { base.isDirectory(url) }
    func resolvingSymlinks(_ url: URL) -> URL { url }
    func write(_ text: String, to url: URL) throws { throw ConfigFileSystemError("disk full") }
    func copyItem(_ source: URL, to destination: URL) throws { throw ConfigFileSystemError("disk full") }
}

final class RecordingFileSystem: ConfigFileSystem, Sendable {
    struct Write: Sendable {
        let text: String
        let onMainThread: Bool
    }

    private let base: MemoryFileSystem
    private let slowFirstWrite: Double
    private let recorded = Mutex<[Write]>([])

    init(_ base: MemoryFileSystem, slowFirstWrite: Double) {
        self.base = base
        self.slowFirstWrite = slowFirstWrite
    }

    var writes: [Write] { recorded.withLock { $0 } }

    func read(_ url: URL) throws -> String { try base.read(url) }
    func contentsOfDirectory(_ url: URL) throws -> [URL] { try base.contentsOfDirectory(url) }
    func exists(_ url: URL) -> Bool { base.exists(url) }
    func isDirectory(_ url: URL) -> Bool { base.isDirectory(url) }
    func resolvingSymlinks(_ url: URL) -> URL { url }
    func copyItem(_ source: URL, to destination: URL) throws { try base.copyItem(source, to: destination) }

    func write(_ text: String, to url: URL) throws {
        let isFirst = recorded.withLock { $0.isEmpty }
        if isFirst { Thread.sleep(forTimeInterval: slowFirstWrite) }
        recorded.withLock { $0.append(Write(text: text, onMainThread: Thread.isMainThread)) }
        try base.write(text, to: url)
    }
}
