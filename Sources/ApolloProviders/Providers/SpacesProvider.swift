import Foundation
import ApolloConfig
import ApolloRuntime

@MainActor
public final class SpacesProvider: BaseProvider {
    static let pollInterval: Double = 5
    static let settleDelay: Double = 0.5
    static let stepDelay: Double = 0.12

    private let source: any SpacesSource
    private var current: DisplaySpaces?
    private var lastState: DisplaySpaces??
    private var loggedMissing = false

    public init(source: any SpacesSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("spaces"), clock: clock)
    }

    override func didStart() {
        lastState = nil
        source.observeChanges { [weak self] in
            guard let self else { return }
            self.refresh()
            self.timers.once("settle", after: Self.settleDelay) { [weak self] in
                self?.refresh()
            }
        }
        timers.set("poll", every: Self.pollInterval, active: true, immediately: true) { [weak self] in
            self?.refresh()
        }
    }

    override func didStop() {
        source.stopObserving()
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        switch arguments.action {
        case "spaces.switch":
            let number = try arguments.number(0)
            guard let active = activeIndex(), let count = current?.spaces.count else {
                warn("spaces.switch: spaces are unavailable")
                return .null
            }
            let index = Int(min(max(number, 1), Double(count)))
            step(index - active, action: arguments.action)
        case "spaces.next":
            step(1, action: arguments.action)
        case "spaces.previous":
            step(-1, action: arguments.action)
        case "spaces.mission-control":
            source.missionControl()
        default:
            throw ProviderActionError.unknownAction(arguments.action)
        }
        return .null
    }

    private func step(_ delta: Int, action: String) {
        guard source.available else {
            warn("\(action): spaces are unavailable")
            return
        }
        guard source.accessibilityTrusted else {
            warn("\(action) needs the accessibility permission")
            return
        }
        guard delta != 0 else { return }
        let right = delta > 0
        for index in 0..<abs(delta) {
            if index == 0 {
                source.step(right: right)
            } else {
                timers.once("step-\(index)", after: Double(index) * Self.stepDelay) { [weak self] in
                    self?.source.step(right: right)
                }
            }
        }
    }

    private func activeIndex() -> Int? {
        guard let current, let active = current.activeID else { return nil }
        return current.spaces.firstIndex { $0.id == active }.map { $0 + 1 }
    }

    private func refresh() {
        guard isRunning else { return }
        if !source.available, !loggedMissing {
            loggedMissing = true
            note("SkyLight functions for spaces are missing, spaces stay empty")
        }
        let displays = source.read()
        let main = Self.pick(displays, main: source.mainScreen)
        current = main
        publish("list", Self.list(main))
        publish("current", ProviderValue.number(activeIndex()))
        publish("count", .number(Double(main?.spaces.count ?? 0)))
        publish("all", .list(displays.map { .record(Record([("screen", .string($0.screen)), ("list", Self.list($0))])) }))
        if let lastState, lastState != main {
            emit("spaces.changed")
        }
        lastState = .some(main)
    }

    static func pick(_ displays: [DisplaySpaces], main: String?) -> DisplaySpaces? {
        if let main, let match = displays.first(where: { $0.screen.caseInsensitiveCompare(main) == .orderedSame }) {
            return match
        }
        return displays.first { $0.screen == "Main" } ?? displays.first
    }

    static func list(_ display: DisplaySpaces?) -> Value {
        guard let display else { return .list([]) }
        return .list(display.spaces.enumerated().map { offset, space in
            .record(Record([
                ("id", .number(Double(space.id))),
                ("index", .number(Double(offset + 1))),
                ("active", .bool(space.id == display.activeID)),
                ("fullscreen", .bool(space.fullscreen)),
            ]))
        })
    }
}
