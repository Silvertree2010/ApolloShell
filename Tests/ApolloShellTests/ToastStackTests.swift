import Testing
import Foundation
import ApolloBase
import ApolloConfig
import ApolloRuntime
@testable import ApolloShell

@MainActor
final class ToastClock {
    var time = Date(timeIntervalSinceReferenceDate: 0)
    var pending: [(TimeInterval, DispatchWorkItem)] = []

    func install(_ center: ToastCenter) {
        center.now = { [unowned self] in self.time }
        center.schedule = { [unowned self] delay, work in self.pending.append((delay, work)) }
    }

    func advance(to seconds: TimeInterval) {
        time = Date(timeIntervalSinceReferenceDate: seconds)
        let due = pending
        pending.removeAll()
        for (_, work) in due where !work.isCancelled { work.perform() }
    }
}

@MainActor
@Suite("Befund 4: notify und Toast-Stapel")
struct ToastStackTests {
    static let config = """
    toast "default" max=2 duration="3s" {
        row {
            on-click { toast.dismiss }
            text "{toast.title}"
        }
    }
    """

    func rows(_ harness: ShellHarness) -> [ElementInstance] {
        harness.runtime.surface("default", screenKey: ShellHarness.a.key)?.root ?? []
    }

    func titles(_ harness: ShellHarness) -> [String] {
        rows(harness).compactMap { row in
            guard case .string(let text)? = row.children.first?.arguments.first?.value else { return nil }
            return text
        }
    }

    func field(_ row: ElementInstance, _ name: String) -> Value? {
        guard case .record(let toast)? = row.scope["toast"] else { return nil }
        return toast[name]
    }

    @Test("max, duration, Warteschlange mit queued, remaining, toast.dismiss, Schliessen wenn leer")
    func stack() async throws {
        let harness = try ShellHarness(Self.config)
        let clock = ToastClock()
        clock.install(harness.shell.toasts)
        try await harness.start()
        for (second, title) in [(0.0, "A"), (1.0, "B"), (2.0, "C")] {
            clock.time = Date(timeIntervalSinceReferenceDate: second)
            _ = try await harness.shell.runActions("notify title=\"\(title)\" kind=\"success\"")
        }
        harness.settle()
        #expect(harness.runtime.surface("default", screenKey: ShellHarness.a.key)?.isOpen == true)
        #expect(titles(harness) == ["A", "B"])
        #expect(rows(harness).first.flatMap { field($0, "kind") } == .string("success"))
        #expect(rows(harness).first.flatMap { field($0, "queued") } == .bool(false))

        clock.advance(to: 3)
        harness.settle()
        #expect(titles(harness) == ["B", "C"])
        #expect(rows(harness).last.flatMap { field($0, "queued") } == .bool(true))
        #expect(rows(harness).first.flatMap { field($0, "remaining") } == .number(1))

        let first = try #require(rows(harness).first)
        await harness.runtime.trigger("on-click", on: first.identity, event: Record())?.value
        harness.settle()
        #expect(titles(harness) == ["C"])

        clock.advance(to: 5)
        harness.settle()
        #expect(titles(harness).isEmpty)
        #expect(harness.runtime.surface("default", screenKey: ShellHarness.a.key)?.isOpen == true)
        clock.advance(to: 5.5)
        harness.settle()
        #expect(harness.runtime.surface("default", screenKey: ShellHarness.a.key)?.isOpen == false)
        #expect(harness.shell.overlay.problems.isEmpty)
        harness.shell.shutdown()
    }

    @Test("newest=first dreht die Reihenfolge, duration der Aktion gilt, fehlender Stil warnt")
    func newestFirstAndWarning() async throws {
        let harness = try ShellHarness("""
        toast "default" newest="first" duration="2s" {
            row { text "{toast.title}" }
        }
        """)
        let clock = ToastClock()
        clock.install(harness.shell.toasts)
        try await harness.start()
        _ = try await harness.shell.runActions("notify title=\"A\" duration=\"10s\"")
        _ = try await harness.shell.runActions("notify title=\"B\"")
        harness.settle()
        #expect(titles(harness) == ["B", "A"])
        clock.advance(to: 2)
        harness.settle()
        #expect(titles(harness) == ["A"])
        #expect(harness.shell.overlay.problems.isEmpty)
        _ = try await harness.shell.runActions("notify title=\"X\" style=\"missing\"")
        harness.settle()
        #expect(harness.shell.overlay.problems.contains { $0.message.contains("toast \"missing\"") })
        harness.shell.shutdown()
    }

    @Test("max mit riesiger Zahl stürzt nicht ab und zeigt alle")
    func hugeMax() async throws {
        let harness = try ShellHarness("""
        toast "default" max=1e20 {
            row { text "{toast.title}" }
        }
        """)
        let clock = ToastClock()
        clock.install(harness.shell.toasts)
        try await harness.start()
        _ = try await harness.shell.runActions("notify title=\"A\"")
        _ = try await harness.shell.runActions("notify title=\"B\"")
        harness.settle()
        #expect(titles(harness) == ["A", "B"])
        harness.shell.shutdown()
    }
}
