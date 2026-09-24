import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("VarStore")
struct VarStoreTests {
    func makeStore(clock: ManualRuntimeClock = ManualRuntimeClock()) -> (SignalStore, ManualFlushScheduler, BindingEngine, VarStore, ManualRuntimeClock) {
        let scheduler = ManualFlushScheduler()
        let store = SignalStore(scheduler: scheduler)
        let engine = BindingEngine(store: store, evaluator: BindingTestHarness.evaluator())
        let vars = VarStore(store: store, bindings: engine, clock: clock)
        return (store, scheduler, engine, vars, clock)
    }

    func decl(_ name: String, type: ValueType, defaultText: String, persist: Bool = false, derived: String? = nil, span: SourceSpan = .synthetic("test")) -> VarDecl {
        let template = ValueTemplate.scalar(try! CompiledValueBuilderAccess.compile("{\(defaultText)}"))
        let derivedCompiled: CompiledValue? = derived.map { try! CompiledValueBuilderAccess.compile("{\($0)}") }
        return VarDecl(name: name, type: type, defaultValue: template, persist: persist, derived: derivedCompiled, span: span)
    }

    @Test("Vorgabewert wird beim ersten Entstehen gesetzt")
    func declareUsesDefault() {
        let (_, _, _, vars, _) = makeStore()
        vars.declare([decl("theme", type: .string, defaultText: "'dark'")], persisted: [:], shell: Record())
        #expect(vars.value("theme") == .string("dark"))
    }

    @Test("Gespeicherter Wert überschreibt die Vorgabe bei passendem Typ")
    func declareUsesPersistedValueWhenTypeMatches() {
        let (_, _, _, vars, _) = makeStore()
        vars.declare([decl("theme", type: .string, defaultText: "'dark'")], persisted: ["theme": .string("light")], shell: Record())
        #expect(vars.value("theme") == .string("light"))
    }

    @Test("Gespeicherter Wert mit falschem Typ fällt auf die Vorgabe zurück, mit Warnung")
    func declareDiscardsWrongTypedPersistedValue() {
        let (_, _, _, vars, _) = makeStore()
        var warnings: [Diagnostic] = []
        vars.onWarning = { warnings.append($0) }
        vars.declare([decl("count", type: .number, defaultText: "0")], persisted: ["count": .string("oops")], shell: Record())
        #expect(vars.value("count") == .number(0))
        #expect(warnings.count == 1)
    }

    @Test("Vorgabe darf shell.* lesen")
    func defaultReadsShell() {
        let (_, _, _, vars, _) = makeStore()
        var shell = Record()
        shell["fresh-install"] = .bool(true)
        vars.declare([decl("key", type: .string, defaultText: "shell.fresh-install ? 'alt+space' : 'f20'")], persisted: [:], shell: shell)
        #expect(vars.value("key") == .string("alt+space"))
    }

    @Test("set mit richtigem Typ ändert den Wert")
    func setChangesValue() {
        let (_, _, _, vars, _) = makeStore()
        vars.declare([decl("count", type: .number, defaultText: "0")], persisted: [:], shell: Record())
        let ok = vars.set("count", .number(5), for: nil)
        #expect(ok)
        #expect(vars.value("count") == .number(5))
    }

    @Test("set mit falschem Typ wird abgelehnt, alter Wert bleibt, Warnung")
    func setRejectsWrongType() {
        let (_, _, _, vars, _) = makeStore()
        var warnings: [Diagnostic] = []
        vars.onWarning = { warnings.append($0) }
        vars.declare([decl("count", type: .number, defaultText: "0")], persisted: [:], shell: Record())
        let ok = vars.set("count", .string("nope"), for: nil)
        #expect(!ok)
        #expect(vars.value("count") == .number(0))
        #expect(warnings.count == 1)
    }

    @Test("set prüft den Typ für jeden ValueType", arguments: [
        (ValueType.string, [true, true, false, false, false, false, false]),
        (ValueType.number, [false, false, true, false, false, false, false]),
        (ValueType.bool, [false, false, false, true, false, false, false]),
        (ValueType.list, [false, false, false, false, true, false, false]),
        (ValueType.record, [false, false, false, false, false, true, false]),
        (ValueType.any, [true, true, true, true, true, true, true]),
        (ValueType.enumeration(["a", "b"]), [true, false, false, false, false, false, false])
    ])
    func setChecksEveryValueType(type: ValueType, expected: [Bool]) {
        let samples: [Value] = [.string("a"), .string("z"), .number(1), .bool(true), .list([.number(1)]), .record(Record([("k", .number(1))])), .null]
        for (sample, accepted) in zip(samples, expected) {
            let (_, _, _, vars, _) = makeStore()
            var warnings: [Diagnostic] = []
            vars.onWarning = { warnings.append($0) }
            let template = ValueTemplate.scalar(try! CompiledValueBuilderAccess.compile("{'a'}"))
            vars.declare([VarDecl(name: "slot", type: type, defaultValue: template, persist: false, derived: nil, span: .synthetic("test"))], persisted: [:], shell: Record())
            let before = vars.value("slot")
            #expect(vars.set("slot", sample, for: nil) == accepted, "\(type) with \(sample)")
            #expect(vars.value("slot") == (accepted ? sample : before), "\(type) with \(sample)")
            #expect(warnings.count == (accepted ? 0 : 1), "\(type) with \(sample)")
        }
    }

    @Test("type any nimmt alles")
    func anyAcceptsEverything() {
        let (_, _, _, vars, _) = makeStore()
        vars.declare([decl("payload", type: .any, defaultText: "0")], persisted: [:], shell: Record())
        #expect(vars.set("payload", .string("text"), for: nil))
        #expect(vars.value("payload") == .string("text"))
        #expect(vars.set("payload", .bool(true), for: nil))
        #expect(vars.value("payload") == .bool(true))
    }

    @Test("reset stellt die Vorgabe wieder her")
    func resetRestoresDefault() {
        let (_, _, _, vars, _) = makeStore()
        vars.declare([decl("count", type: .number, defaultText: "7")], persisted: [:], shell: Record())
        vars.set("count", .number(99), for: nil)
        vars.reset("count")
        #expect(vars.value("count") == .number(7))
    }

    @Test("set … for= stellt nach Ablauf den Wert davor wieder her")
    func setForRestoresAfterExpiry() {
        let (store, _, _, vars, clock) = makeStore()
        vars.declare([decl("volume", type: .number, defaultText: "0.5")], persisted: [:], shell: Record())
        _ = vars.set("volume", .number(0.7), for: 0.5)
        #expect(vars.value("volume") == .number(0.7))
        #expect(store.value(DependencyPath("var", ["volume"])) == .number(0.7))
        clock.advance(by: 0.5)
        #expect(vars.value("volume") == .number(0.5))
    }

    @Test("Ein weiteres set … for= startet die Zeit neu und stellt auf den Wert vor dem ersten zurück")
    func secondSetForRestartsTimerAndKeepsOriginalBase() {
        let (_, _, _, vars, clock) = makeStore()
        vars.declare([decl("volume", type: .number, defaultText: "0.5")], persisted: [:], shell: Record())
        _ = vars.set("volume", .number(0.7), for: 1.0)
        clock.advance(by: 0.6)
        _ = vars.set("volume", .number(0.9), for: 1.0)
        #expect(vars.value("volume") == .number(0.9))
        clock.advance(by: 0.6)
        #expect(vars.value("volume") == .number(0.9))
        clock.advance(by: 0.5)
        #expect(vars.value("volume") == .number(0.5))
    }

    @Test("set ohne for beendet eine laufende vorübergehende Phase dauerhaft")
    func plainSetEndsTransientPhasePermanently() {
        let (_, _, _, vars, clock) = makeStore()
        vars.declare([decl("volume", type: .number, defaultText: "0.5")], persisted: [:], shell: Record())
        _ = vars.set("volume", .number(0.7), for: 1.0)
        _ = vars.set("volume", .number(0.3), for: nil)
        clock.advance(by: 2)
        #expect(vars.value("volume") == .number(0.3))
    }

    @Test("Persistierter Wert während vorübergehender Phase ist immer der Basiswert")
    func persistedSnapshotUsesBaseValueDuringTransient() {
        let (_, _, _, vars, clock) = makeStore()
        var snapshots: [[String: Value]] = []
        vars.onPersist = { snapshots.append($0) }
        vars.declare([decl("volume", type: .number, defaultText: "0.5", persist: true)], persisted: [:], shell: Record())
        _ = vars.set("volume", .number(0.6), for: nil)
        clock.advance(by: 0.5)
        #expect(snapshots.last?["volume"] == .number(0.6))
        _ = vars.set("volume", .number(0.9), for: 5.0)
        vars.flushPendingSaves()
        #expect(snapshots.last?["volume"] == .number(0.6))
    }

    @Test("Abgeleitetes var ist faul: keine Auswertung ohne Nachfrage")
    func derivedVarIsLazy() {
        let (_, scheduler, engine, vars, _) = makeStore()
        vars.declare([
            decl("base", type: .number, defaultText: "1"),
            decl("doubled", type: .number, defaultText: "0", derived: "var.base * 2")
        ], persisted: [:], shell: Record())
        #expect(engine.evaluationCount == 0)
        vars.set("base", .number(5), for: nil)
        scheduler.runPending()
        #expect(engine.evaluationCount == 0)
        #expect(vars.value("doubled") == .null)
    }

    @Test("Abgeleitetes var wird einmal für 10 Leser ausgewertet")
    func derivedVarEvaluatesOnceForManyReaders() {
        let (store, scheduler, engine, vars, _) = makeStore()
        vars.declare([
            decl("base", type: .number, defaultText: "1"),
            decl("doubled", type: .number, defaultText: "0", derived: "var.base * 2")
        ], persisted: [:], shell: Record())
        var results: [[Value]] = Array(repeating: [], count: 10)
        var handles: [BindingHandle] = []
        for index in 0..<10 {
            let handle = engine.bind(BindingTestHarness.source("{var.doubled}"), scope: LocalScope(), active: true) { results[index].append($0) }
            handles.append(handle)
        }
        for result in results {
            #expect(result == [.number(2)])
        }
        #expect(store.value(DependencyPath("var", ["doubled"])) == .number(2))
        #expect(engine.evaluationCount == 11)
        let before = engine.evaluationCount
        vars.set("base", .number(4), for: nil)
        scheduler.runPending()
        #expect(engine.evaluationCount - before == 11)
        for result in results {
            #expect(result == [.number(2), .number(8)])
        }
    }

    @Test("Abgeleitetes var wird ohne Nachfrage inaktiv und Kette A←B←C bleibt in einem Flush konsistent")
    func derivedChainStaysConsistentInOneFlush() {
        let (store, scheduler, engine, vars, _) = makeStore()
        vars.declare([
            decl("a", type: .number, defaultText: "1"),
            decl("b", type: .number, defaultText: "0", derived: "var.a + 1"),
            decl("c", type: .number, defaultText: "0", derived: "var.b + 1")
        ], persisted: [:], shell: Record())
        var seen: [Value] = []
        let handle = engine.bind(BindingTestHarness.source("{var.c}"), scope: LocalScope(), active: true) { seen.append($0) }
        #expect(handle.currentValue == .number(3))
        seen.removeAll()

        store.set(DependencyPath("var", ["a"]), .number(10))
        scheduler.runPending()

        #expect(seen == [.number(12)])
    }

    @Test("Zyklus A→B→A: Diagnose mit Kette, beide bleiben null, Rest läuft")
    func cycleProducesDiagnosticAndNullValues() {
        let (_, _, _, vars, _) = makeStore()
        var warnings: [Diagnostic] = []
        vars.onWarning = { warnings.append($0) }
        vars.declare([
            decl("ok", type: .number, defaultText: "5"),
            decl("a", type: .number, defaultText: "0", derived: "var.b"),
            decl("b", type: .number, defaultText: "0", derived: "var.a")
        ], persisted: [:], shell: Record())
        #expect(vars.value("a") == .null)
        #expect(vars.value("b") == .null)
        #expect(vars.value("ok") == .number(5))
        #expect(warnings.count == 1)
        #expect(warnings[0].severity == .error)
    }

    @Test("Selbstbezug ist ein Zyklus")
    func selfReferenceIsACycle() {
        let (_, _, _, vars, _) = makeStore()
        var warnings: [Diagnostic] = []
        vars.onWarning = { warnings.append($0) }
        vars.declare([decl("loop", type: .number, defaultText: "0", derived: "var.loop + 1")], persisted: [:], shell: Record())
        #expect(vars.value("loop") == .null)
        #expect(warnings.count == 1)
    }

    @Test("Reload behält den Wert bei gleichem Namen und Typ, neue Vorgabe ändert nichts")
    func reloadKeepsValueWhenTypeUnchanged() {
        let (_, _, _, vars, _) = makeStore()
        vars.declare([decl("count", type: .number, defaultText: "1")], persisted: [:], shell: Record())
        vars.set("count", .number(42), for: nil)
        vars.declare([decl("count", type: .number, defaultText: "99")], persisted: [:], shell: Record())
        #expect(vars.value("count") == .number(42))
    }

    @Test("Reload mit anderem Typ setzt auf die neue Vorgabe zurück")
    func reloadWithTypeChangeResets() {
        let (_, _, _, vars, _) = makeStore()
        vars.declare([decl("count", type: .number, defaultText: "1")], persisted: [:], shell: Record())
        vars.set("count", .number(42), for: nil)
        vars.declare([decl("count", type: .string, defaultText: "'hi'")], persisted: [:], shell: Record())
        #expect(vars.value("count") == .string("hi"))
    }

    @Test("Reload während for= läuft der Timer weiter, wenn Typ gleich bleibt")
    func reloadKeepsTransientTimerRunningWhenTypeUnchanged() {
        let (_, _, _, vars, clock) = makeStore()
        vars.declare([decl("volume", type: .number, defaultText: "0.5")], persisted: [:], shell: Record())
        _ = vars.set("volume", .number(0.9), for: 1.0)
        vars.declare([decl("volume", type: .number, defaultText: "0.5")], persisted: [:], shell: Record())
        #expect(vars.value("volume") == .number(0.9))
        clock.advance(by: 1.0)
        #expect(vars.value("volume") == .number(0.5))
    }

    @Test("Reload während for= mit Typwechsel verwirft den Timer")
    func reloadWithTypeChangeDiscardsTransientTimer() {
        let (_, _, _, vars, clock) = makeStore()
        vars.declare([decl("volume", type: .number, defaultText: "0.5")], persisted: [:], shell: Record())
        _ = vars.set("volume", .number(0.9), for: 1.0)
        vars.declare([decl("volume", type: .string, defaultText: "'x'")], persisted: [:], shell: Record())
        clock.advance(by: 1.0)
        #expect(vars.value("volume") == .string("x"))
    }

    @Test("toggle-var auf ein nicht-bool ist eine Warnung über set")
    func togglingNonBoolWarns() {
        let (_, _, _, vars, _) = makeStore()
        var warnings: [Diagnostic] = []
        vars.onWarning = { warnings.append($0) }
        vars.declare([decl("label", type: .string, defaultText: "'hi'")], persisted: [:], shell: Record())
        let ok = vars.set("label", .bool(true), for: nil)
        #expect(!ok)
        #expect(warnings.count == 1)
    }

    @Test("Vorgabe liest alten Namen aus der Statusdatei")
    func defaultReadsOldNameFromPersistedState() {
        let (_, _, _, vars, _) = makeStore()
        vars.declare([decl("new-key", type: .string, defaultText: "var.old-key ?? 'fallback'")], persisted: ["old-key": .string("migrated")], shell: Record())
        #expect(vars.value("new-key") == .string("migrated"))
    }

    @Test("Kette mit 1000 Gliedern: ein Leser auf dem letzten Glied bekommt den Wert schnell und ohne Stack-Überlauf")
    func longChainWithReaderIsFast() {
        let (store, _, engine, vars, _) = makeStore()
        var decls: [VarDecl] = [decl("v0", type: .number, defaultText: "1")]
        for index in 1..<1000 {
            decls.append(decl("v\(index)", type: .number, defaultText: "0", derived: "var.v\(index - 1) + 1"))
        }
        vars.declare(decls, persisted: [:], shell: Record())
        let clock = ContinuousClock()
        let start = clock.now
        let handle = engine.bind(BindingTestHarness.source("{var.v999}"), scope: LocalScope(), active: true) { _ in }
        let activation = clock.now - start
        #expect(handle.currentValue == .number(1000))
        #expect(activation < .seconds(1), "activation took \(activation)")
        let stopStart = clock.now
        handle.cancel()
        let deactivation = clock.now - stopStart
        #expect(deactivation < .seconds(1), "deactivation took \(deactivation)")
        #expect(store.demandedPaths(root: "var").isEmpty)
    }

    @Test("Kette a←b←c mit a aus einem Provider bleibt nach Änderung frisch, in jeder Namensreihenfolge")
    func derivedChainFromProviderStaysFreshForAnyNameOrder() {
        var staleAfterBind = 0
        var staleAfterChange = 0
        for variant in 0..<40 {
            let (store, scheduler, engine, vars, _) = makeStore()
            let a = "a\(variant)"
            let b = "b\(variant)"
            let c = "c\(variant)"
            store.set(DependencyPath("p", ["x"]), .number(1))
            vars.declare([
                decl(c, type: .number, defaultText: "0", derived: "var.\(b) + 1"),
                decl(a, type: .number, defaultText: "0", derived: "p.x"),
                decl(b, type: .number, defaultText: "0", derived: "var.\(a) + 1")
            ], persisted: [:], shell: Record())
            let handle = engine.bind(BindingTestHarness.source("{var.\(c)}"), scope: LocalScope(), active: true) { _ in }
            if handle.currentValue != .number(3) { staleAfterBind += 1 }
            store.set(DependencyPath("p", ["x"]), .number(10))
            scheduler.runPending()
            if handle.currentValue != .number(12) { staleAfterChange += 1 }
        }
        #expect(staleAfterBind == 0, "stale after bind in \(staleAfterBind)/40")
        #expect(staleAfterChange == 0, "stale after change in \(staleAfterChange)/40")
    }

    @Test("Abgeleitetes var funktioniert, egal ob ProviderHost vor oder nach VarStore entsteht")
    func derivedVarWorksWithProviderHostInEitherOrder() {
        for hostFirst in [true, false] {
            let scheduler = ManualFlushScheduler()
            let store = SignalStore(scheduler: scheduler)
            let engine = BindingEngine(store: store, evaluator: BindingTestHarness.evaluator())
            var host: ProviderHost?
            if hostFirst { host = ProviderHost(store: store) }
            let vars = VarStore(store: store, bindings: engine, clock: ManualRuntimeClock())
            if !hostFirst { host = ProviderHost(store: store) }
            let provider = StubProvider(id: "p")
            host?.register(provider)
            vars.declare([
                decl("base", type: .number, defaultText: "1"),
                decl("doubled", type: .number, defaultText: "0", derived: "var.base * 2 + (p.x ?? 0)")
            ], persisted: [:], shell: Record())
            let handle = engine.bind(BindingTestHarness.source("{var.doubled}"), scope: LocalScope(), active: true) { _ in }
            scheduler.runPending()
            #expect(handle.currentValue == .number(2), "hostFirst=\(hostFirst)")
            #expect(provider.startCount == 1, "hostFirst=\(hostFirst)")
        }
    }

    @Test("Config-Wechsel verwirft alle Werte, liest die neue Statusdatei und schreibt die alte vorher nach")
    func switchConfigDiscardsSlots() {
        let (_, _, _, vars, clock) = makeStore()
        var snapshots: [[String: Value]] = []
        vars.onPersist = { snapshots.append($0) }
        vars.declare([
            decl("count", type: .number, defaultText: "0", persist: true),
            decl("volume", type: .number, defaultText: "0.5")
        ], persisted: ["count": .number(1)], shell: Record())
        vars.set("count", .number(42), for: nil)
        vars.set("volume", .number(0.9), for: 1.0)
        vars.switchConfig([
            decl("count", type: .number, defaultText: "0", persist: true),
            decl("volume", type: .number, defaultText: "0.2")
        ], persisted: ["count": .number(7)], shell: Record())
        #expect(snapshots.last?["count"] == .number(42))
        #expect(vars.value("count") == .number(7))
        #expect(vars.value("volume") == .number(0.2))
        clock.advance(by: 2)
        #expect(vars.value("volume") == .number(0.2))
    }

    @Test("Zyklus a→b→c→a mit Umweg a→d→b: alle vier gehören zum Zyklus, eine Diagnose mit Ort und Kette, stabil")
    func cycleWithDetourMarksWholeComponent() {
        var failures: [String] = []
        for variant in 0..<40 {
            let (_, _, _, vars, _) = makeStore()
            var warnings: [Diagnostic] = []
            vars.onWarning = { warnings.append($0) }
            let a = "a\(variant)"
            let b = "b\(variant)"
            let c = "c\(variant)"
            let d = "d\(variant)"
            let span: (String) -> SourceSpan = { .synthetic("decl-\($0)") }
            vars.declare([
                decl(d, type: .number, defaultText: "0", derived: "var.\(b)", span: span(d)),
                decl(c, type: .number, defaultText: "0", derived: "var.\(a)", span: span(c)),
                decl("ok", type: .number, defaultText: "5"),
                decl(b, type: .number, defaultText: "0", derived: "var.\(c)", span: span(b)),
                decl(a, type: .number, defaultText: "0", derived: "var.\(b) + var.\(d)", span: span(a))
            ], persisted: [:], shell: Record())
            let expected = Diagnostic(
                .error,
                "cyclic derived var: \(a) -> \(b) -> \(c) -> \(a)",
                span: span(a),
                notes: [DiagnosticNote("'\(d)' is part of the same cycle", span: span(d))]
            )
            if warnings != [expected] { failures.append("\(variant): \(warnings.map(\.message)) \(warnings.map(\.notes))") }
            if vars.value("ok") != .number(5) { failures.append("\(variant): ok") }
        }
        #expect(failures.isEmpty, "\(failures.count)/40: \(failures.prefix(3))")
    }

    @Test("reset nach Reload nutzt die neue Vorgabe")
    func resetAfterReloadUsesNewDefault() {
        let (_, _, _, vars, _) = makeStore()
        vars.declare([decl("count", type: .number, defaultText: "1")], persisted: [:], shell: Record())
        vars.set("count", .number(42), for: nil)
        vars.declare([decl("count", type: .number, defaultText: "99")], persisted: [:], shell: Record())
        #expect(vars.value("count") == .number(42))
        vars.reset("count")
        #expect(vars.value("count") == .number(99))
    }

    @Test("Ein nicht mehr deklariertes var verschwindet aus dem Store")
    func removedVarVanishesFromStore() {
        let (store, scheduler, engine, vars, _) = makeStore()
        vars.declare([
            decl("keep", type: .number, defaultText: "1"),
            decl("gone", type: .number, defaultText: "2"),
            decl("gone-derived", type: .number, defaultText: "0", derived: "var.keep + 1")
        ], persisted: [:], shell: Record())
        let reader = engine.bind(BindingTestHarness.source("{var.gone-derived}"), scope: LocalScope(), active: true) { _ in }
        #expect(reader.currentValue == .number(2))
        vars.declare([decl("keep", type: .number, defaultText: "1")], persisted: [:], shell: Record())
        scheduler.runPending()
        guard case .record(let record) = store.value(DependencyPath("var", [])) else {
            Issue.record("var root is not a record")
            return
        }
        #expect(record.keys == ["keep"])
        #expect(reader.currentValue == .null)
    }

}

enum CompiledValueBuilderAccess {
    static func compile(_ text: String) throws -> CompiledValue {
        let template = try ExpressionParser.parseTemplate(text, span: .synthetic("test")).get()
        return CompiledValue(template: template, dependencies: template.dependencies(locals: []), span: .synthetic("test"))
    }
}
