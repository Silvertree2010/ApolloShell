import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class ScriptSourcesProvider: BaseProvider {
    static let lineLimit = 1000

    private final class Entry {
        let spec: ScriptSourceSpec
        var value: Value?
        var error: String?
        var when = true
        var handle: (any ScriptHandle)?
        var generation = 0
        var failures = 0
        var startedAt = Date.distantPast
        var lines: [Value] = []

        init(_ spec: ScriptSourceSpec) {
            self.spec = spec
        }
    }

    public let kind: ScriptKind
    private let runner: any ScriptRunner
    private var entries: [Entry]

    public init(kind: ScriptKind, sources: [ScriptSourceSpec], runner: any ScriptRunner, clock: any RuntimeClock) {
        self.kind = kind
        self.runner = runner
        entries = sources.map(Entry.init)
        super.init(schema: Self.schema(kind, sources), clock: clock)
    }

    public static func errorField(_ name: String) -> String {
        "\(name)-error"
    }

    public static func schema(_ kind: ScriptKind, _ sources: [ScriptSourceSpec]) -> ProviderSchema {
        ProviderSchema(
            id: kind.rawValue,
            feature: "script-sources",
            fields: sources.flatMap { spec in [
                FieldSchema(path: [spec.name], type: .any, nullable: true, update: kind == .poll ? .poll(seconds: spec.interval) : .push, doc: spec.command),
                FieldSchema(path: [errorField(spec.name)], type: .string, nullable: true, update: .push, doc: "last error of \(spec.name)"),
            ] },
            doc: kind == .poll ? "poll script sources" : "listen script sources"
        )
    }

    override func didStart() {
        for entry in entries {
            entry.failures = 0
            publish(entry)
        }
    }

    override func didChangeDemand() {
        reconcile()
    }

    override func didConfigure(_ settings: Record) {
        for entry in entries {
            guard case .record(let options) = settings[entry.spec.name] ?? .null else { continue }
            if case .bool(let flag) = options["when"] ?? .null { entry.when = flag }
        }
        if isRunning { reconcile() }
    }

    override func didStop() {
        for entry in entries { halt(entry) }
    }

    private func reconcile() {
        for entry in entries {
            let active = isRunning && entry.when && demand.wantsAny([entry.spec.name, Self.errorField(entry.spec.name)])
            switch kind {
            case .poll:
                timers.set("run.\(entry.spec.name)", every: entry.spec.interval, active: active, immediately: true) { [weak self, weak entry] in
                    guard let self, let entry else { return }
                    self.runPoll(entry)
                }
                if !active { halt(entry) }
            case .listen:
                if active {
                    if entry.handle == nil, !timers.isActive("restart.\(entry.spec.name)") { launch(entry) }
                } else {
                    halt(entry)
                }
            }
        }
    }

    private func halt(_ entry: Entry) {
        entry.generation += 1
        entry.handle?.terminate()
        entry.handle = nil
        timers.cancel("timeout.\(entry.spec.name)")
        timers.cancel("restart.\(entry.spec.name)")
    }

    private func runPoll(_ entry: Entry) {
        guard entry.handle == nil else { return }
        entry.generation += 1
        let generation = entry.generation
        let name = entry.spec.name
        var finished = false
        let handle = runner.run(entry.spec.command) { [weak self, weak entry] status, output in
            guard let self, let entry, entry.generation == generation else { return }
            finished = true
            entry.handle = nil
            self.timers.cancel("timeout.\(name)")
            if status == 0 {
                self.accept(entry, output)
            } else {
                entry.error = "exit status \(status)"
            }
            self.publish(entry)
        }
        guard entry.generation == generation, !finished else { return }
        guard let handle else {
            entry.error = "could not start \"\(entry.spec.command)\""
            publish(entry)
            return
        }
        entry.handle = handle
        timers.once("timeout.\(name)", after: entry.spec.timeout) { [weak self, weak entry] in
            guard let self, let entry, entry.generation == generation else { return }
            entry.generation += 1
            entry.handle?.terminate()
            entry.handle = nil
            entry.error = "timed out after \(Self.seconds(entry.spec.timeout))"
            self.publish(entry)
        }
    }

    private func launch(_ entry: Entry) {
        entry.generation += 1
        let generation = entry.generation
        entry.startedAt = runner.now
        entry.lines = []
        let handle = runner.stream(entry.spec.command, onLine: { [weak self, weak entry] line in
            guard let self, let entry, entry.generation == generation else { return }
            self.acceptLine(entry, line)
            self.publish(entry)
        }, onExit: { [weak self, weak entry] status in
            guard let self, let entry, entry.generation == generation else { return }
            entry.handle = nil
            self.ended(entry, status: status)
        })
        guard let handle else {
            entry.error = "could not start \"\(entry.spec.command)\""
            ended(entry, status: -1)
            return
        }
        entry.handle = handle
    }

    private func ended(_ entry: Entry, status: Int32) {
        guard isRunning else { return }
        entry.failures = MediaRestart.failures(previous: entry.failures, runtime: runner.now.timeIntervalSince(entry.startedAt))
        guard let delay = MediaRestart.delay(afterFailures: entry.failures) else {
            entry.error = "gave up after \(entry.failures) early exits (last exit status \(status))"
            publish(entry)
            return
        }
        entry.error = "exited with status \(status), restarting in \(Self.seconds(delay))"
        publish(entry)
        timers.once("restart.\(entry.spec.name)", after: delay) { [weak self, weak entry] in
            guard let self, let entry, self.isRunning else { return }
            self.launch(entry)
        }
    }

    private func accept(_ entry: Entry, _ output: String) {
        switch entry.spec.format {
        case .text:
            entry.value = .string(Self.trimmingNewlines(output))
            entry.error = nil
        case .lines:
            entry.value = .list(Self.lines(output).map(Value.string))
            entry.error = nil
        case .json:
            parseJSON(entry, output)
        }
    }

    private func acceptLine(_ entry: Entry, _ line: String) {
        let line = Self.trimmingNewlines(line)
        switch entry.spec.format {
        case .text:
            entry.value = .string(line)
            entry.error = nil
        case .lines:
            entry.lines.append(.string(line))
            if entry.lines.count > Self.lineLimit { entry.lines.removeFirst(entry.lines.count - Self.lineLimit) }
            entry.value = .list(entry.lines)
            entry.error = nil
        case .json:
            parseJSON(entry, line)
        }
    }

    private func parseJSON(_ entry: Entry, _ text: String) {
        if let value = JSONValue.parse(text) {
            entry.value = value
            entry.error = nil
        } else {
            entry.value = .null
            entry.error = "invalid JSON"
        }
    }

    private func publish(_ entry: Entry) {
        guard isRunning else { return }
        publish(entry.spec.name, entry.value ?? entry.spec.initial)
        publish(Self.errorField(entry.spec.name), ProviderValue.string(entry.error))
    }

    static func trimmingNewlines(_ text: String) -> String {
        var result = Substring(text)
        while let last = result.last, last.isNewline { result = result.dropLast() }
        return String(result)
    }

    static func lines(_ text: String) -> [String] {
        trimmingNewlines(text).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }

    static func seconds(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))s" : "\(value)s"
    }
}
