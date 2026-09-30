import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class PowerProvider: BaseProvider {
    static let batteryInterval: Double = 60
    static let textInterval: Double = 60
    static let ruleInterval: Double = 2

    private let source: any PowerSource
    private let guardTimers: ProviderTimers
    private var since: Date?
    private var lid: KeepAwakeLid = .off
    private var lidOwned = false
    private var lidAllowed = false
    private var prompt: Bool?

    public var isOn: Bool { since != nil }

    public init(source: any PowerSource, clock: any RuntimeClock) {
        self.source = source
        guardTimers = ProviderTimers(clock: clock)
        super.init(schema: BuiltinProviderSchemas.schema("power"), clock: clock)
        recover()
    }

    override func didStart() {
        publishState()
    }

    override func didChangeDemand() {
        timers.set("text", every: Self.textInterval, active: demand.wants("keep-awake-text"), immediately: true) { [weak self] in
            self?.publishText()
        }
        timers.set("rule", every: Self.ruleInterval, active: demand.wants("lid-rule-installed"), immediately: true) { [weak self] in
            guard let self else { return }
            self.publish("lid-rule-installed", .bool(self.source.ruleInstalled))
        }
    }

    override func didConfigure(_ settings: Record) {
        let allowed = settings["lid-closed"] == .bool(true)
        guard allowed != lidAllowed else { return }
        lidAllowed = allowed
        guard isOn else { return }
        reconcileLid()
        publishState()
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        switch arguments.action {
        case "power.set-keep-awake":
            set(try arguments.bool(0))
        case "power.toggle-keep-awake":
            set(!isOn)
        case "power.remove-lid-rule":
            source.removeRule { [weak self] _ in
                guard let self, self.isRunning, self.demand.wants("lid-rule-installed") else { return }
                self.publish("lid-rule-installed", .bool(self.source.ruleInstalled))
            }
        default:
            throw ProviderActionError.unknownAction(arguments.action)
        }
        return .null
    }

    public func set(_ on: Bool) {
        guard on != isOn else { return }
        if on {
            guard source.takeAssertion() else {
                warn("power.set-keep-awake: the power assertion could not be created")
                return
            }
            since = source.now
            reconcileLid()
            guardTimers.set("battery", every: Self.batteryInterval, active: true) { [weak self] in
                self?.checkBattery()
            }
        } else {
            source.releaseAssertion()
            since = nil
            guardTimers.cancel("battery")
            reconcileLid()
        }
        publishState()
    }

    public func shutdown() {
        source.releaseAssertion()
        since = nil
        guardTimers.cancelAll()
        if let prompt {
            if prompt { source.cancelAdmin() }
            return
        }
        guard lidOwned else { return }
        if source.sudoSetSleepDisabled(false) || source.adminSync(disableSleep: false) {
            lidReleased()
        }
    }

    private var lidWanted: Bool { isOn && lidAllowed }

    private func checkBattery() {
        guard LidAwake.shouldStop(battery: source.battery()) else { return }
        set(false)
        emit("power.keep-awake-stopped", Record([("reason", .string("battery"))]))
    }

    private func reconcileLid() {
        guard prompt == nil else {
            lid = lidWanted ? .pending : .off
            return
        }
        if lidWanted { enableLid() } else { releaseLid() }
    }

    private func enableLid() {
        guard lid != .on else { return }
        if source.sleepDisabled() == true {
            lidOwned = source.markerExists
            lid = .on
            return
        }
        if source.sudoSetSleepDisabled(true) {
            lidTaken()
            return
        }
        source.writeMarker()
        lid = .pending
        askAdmin(disableSleep: true)
    }

    private func releaseLid() {
        guard lidOwned else {
            lid = .off
            return
        }
        if source.sudoSetSleepDisabled(false) {
            lidReleased()
            return
        }
        lid = .off
        askAdmin(disableSleep: false)
    }

    private func askAdmin(disableSleep: Bool) {
        prompt = disableSleep
        let started = source.askAdmin(disableSleep: disableSleep, installRule: disableSleep && !source.ruleInstalled) { [weak self] ok in
            self?.adminFinished(disableSleep: disableSleep, ok: ok)
        }
        if !started { adminFinished(disableSleep: disableSleep, ok: false) }
    }

    private func adminFinished(disableSleep: Bool, ok: Bool) {
        prompt = nil
        defer { publishState() }
        if disableSleep {
            guard ok else {
                if !lidOwned { source.removeMarker() }
                lid = lidWanted ? .declined : .off
                return
            }
            lidTaken()
            if !lidWanted { releaseLid() }
        } else {
            guard ok else {
                lid = lidWanted ? .on : .off
                if !lidWanted { emit("power.lid-still-awake") }
                return
            }
            lidReleased()
            if lidWanted { enableLid() }
        }
    }

    private func lidTaken() {
        lidOwned = true
        lid = .on
        source.writeMarker()
    }

    private func lidReleased() {
        lidOwned = false
        lid = .off
        source.removeMarker()
    }

    private func recover() {
        guard source.markerExists else { return }
        lidOwned = true
        if source.sleepDisabled() == false || source.sudoSetSleepDisabled(false) {
            lidReleased()
            return
        }
        askAdmin(disableSleep: false)
    }

    private func publishState() {
        guard isRunning else { return }
        publish("keep-awake", .bool(isOn))
        publish("keep-awake-since", since.map(Value.date) ?? .null)
        publish("lid", .string(Self.lidName(lid)))
        publishText()
    }

    private func publishText() {
        publish("keep-awake-text", .string(KeepAwakeText.subtitle(since: since, now: source.now, lid: lid)))
    }

    static func lidName(_ lid: KeepAwakeLid) -> String {
        switch lid {
        case .off: "off"
        case .on: "on"
        case .pending: "pending"
        case .declined: "declined"
        }
    }
}

@MainActor
public final class PermissionsProvider: BaseProvider {
    static let interval: Double = 2
    static let kinds = ["accessibility", "automation", "screen-recording"]

    private let source: any PermissionsSource

    public init(source: any PermissionsSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("permissions"), clock: clock)
    }

    override func didChangeDemand() {
        timers.set("read", every: Self.interval, active: demand.wantsAny(Self.kinds), immediately: true) { [weak self] in
            self?.read()
        }
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        switch arguments.action {
        case "permissions.request-accessibility":
            source.requestAccessibility()
        case "permissions.open":
            let kind = try arguments.string(0)
            guard Self.kinds.contains(kind) else {
                throw ProviderActionError.invalidArgument(action: arguments.action, message: "unknown permission \"\(kind)\"")
            }
            source.open(kind)
        default:
            throw ProviderActionError.unknownAction(arguments.action)
        }
        return .null
    }

    private func read() {
        let state = source.read()
        publish("accessibility", .bool(state.accessibility))
        publish("automation", ProviderValue.bool(state.automation))
        publish("screen-recording", .bool(state.screenRecording))
        publish("screen-capture-bypass", .bool(state.screenCaptureBypass))
    }
}

@MainActor
public final class ShortcutsProvider: BaseProvider {
    static let interval: Double = 5

    private let source: any ShortcutsSource
    private var generation = 0
    private var reading = false

    public init(source: any ShortcutsSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("shortcuts"), clock: clock)
    }

    override func didStart() {
        generation += 1
        reading = false
    }

    override func didChangeDemand() {
        timers.set("list", every: Self.interval, active: demand.wants("list"), immediately: true) { [weak self] in
            self?.request()
        }
    }

    override func didStop() {
        generation += 1
        reading = false
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        guard arguments.action == "run-shortcut" else {
            throw ProviderActionError.unknownAction(arguments.action)
        }
        let name = try arguments.string(0)
        source.run(name) { [weak self] ok in
            guard !ok else { return }
            self?.emit("shortcuts.failed", Record([("name", .string(name))]))
        }
        return .null
    }

    private func request() {
        guard isRunning, !reading else { return }
        reading = true
        let generation = generation
        source.list { [weak self] shortcuts in
            guard let self, generation == self.generation else { return }
            self.reading = false
            self.publish("list", .list((shortcuts ?? []).map { .record(Record([("name", .string($0.name)), ("id", .string($0.id))])) }))
        }
    }
}
