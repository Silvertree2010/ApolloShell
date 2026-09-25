import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloWMCore

@MainActor
public final class WMProvider: BaseProvider {
    static let permissionRetry: Double = 2

    private let engine: any WMEngine
    private let lifecycle: ProviderTimers
    private var settings = WMSettings()
    private var configured = false
    private var requested = false
    private var toggled = false
    private var panels: [PanelReserve] = []
    private var sentReserve: [String: WMReserved]?
    private var last: WMState?
    private var proxyFallback = false
    private var proxyFallbackWarned = false

    public private(set) var isEngineRunning = false

    public init(engine: any WMEngine, clock: any RuntimeClock) {
        self.engine = engine
        lifecycle = ProviderTimers(clock: clock)
        super.init(schema: BuiltinProviderSchemas.schema("wm"), clock: clock)
        engine.onChange = { [weak self] in self?.engineChanged() }
    }

    public var currentSettings: WMSettings { settings }

    public func apply(_ settings: WMSettings?) {
        let next = settings ?? WMSettings()
        let hadBlock = configured
        configured = settings != nil
        let changed = next != self.settings
        self.settings = next
        if !configured || (!hadBlock && configured) {
            toggled = false
        }
        if changed, isEngineRunning {
            engine.configure(effective(next))
        }
        sendReserve(force: changed)
        reconcile()
    }

    public func setPanelReserves(_ panels: [PanelReserve]) {
        guard panels != self.panels else { return }
        self.panels = panels
        sendReserve(force: false)
    }

    public func screensChanged() {
        sendReserve(force: false)
    }

    public func shutdown() {
        lifecycle.cancelAll()
        requested = false
        toggled = false
        if isEngineRunning { halt() }
    }

    override func didConfigure(_ settings: Record) {
        guard case .bool(let enabled) = settings["enabled"] ?? .null else { return }
        if enabled != requested { toggled = false }
        requested = enabled
        reconcile()
    }

    override func didStart() {
        publishAll()
        warnProxyFallback()
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        let action = arguments.action
        switch action {
        case "wm.toggle":
            toggled.toggle()
            reconcile()
            return .null
        case "wm.layout":
            let kind = try arguments.string(0)
            guard let layout = WMSettings.Layout(rawValue: kind) else {
                throw ProviderActionError.invalidArgument(action: action, message: "layout must be dwindle or canvas")
            }
            guard running(action) else { return .null }
            engine.setLayout(layout)
            engineChanged()
            return .null
        case "wm.focus-window":
            guard let id = UInt32(try arguments.string(0)) else {
                throw ProviderActionError.invalidArgument(action: action, message: "argument 1 must be a window id")
            }
            guard running(action) else { return .null }
            if !engine.focusWindow(id) { warn("\(action): no window \(id)") }
            return .null
        default:
            let command = try Self.command(arguments)
            guard running(action) else { return .null }
            engine.perform(command)
            return .null
        }
    }

    public func control(_ argv: [String]) throws -> Value {
        let words = argv.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
        guard let verb = words.first?.lowercased() else {
            throw ProviderActionError.invalidArgument(action: "wm", message: "needs a command")
        }
        let rest = Array(words.dropFirst())
        switch verb {
        case "ping":
            return .string("pong")
        case "windows":
            return isEngineRunning ? Self.windowsValue(engine.state()) : .list([])
        case "state":
            return root()
        case "toggle":
            toggled.toggle()
            reconcile()
            return .string("ok")
        case "layout":
            guard rest.count == 1, let layout = WMSettings.Layout(rawValue: rest[0].lowercased()) else {
                throw ProviderActionError.invalidArgument(action: "wm layout", message: "expected dwindle or canvas")
            }
            try requireRunning()
            engine.setLayout(layout)
            engineChanged()
            return .string("ok")
        case "focus-window":
            guard rest.count == 1, let id = UInt32(rest[0]) else {
                throw ProviderActionError.invalidArgument(action: "wm focus-window", message: "expected a window id")
            }
            try requireRunning()
            guard engine.focusWindow(id) else {
                throw ProviderActionError.invalidArgument(action: "wm focus-window", message: "no window \(id)")
            }
            return .string("ok")
        default:
            guard let command = Command(parsing: words.joined(separator: " ")) else {
                throw ProviderActionError.unknownAction("wm \(words.joined(separator: " "))")
            }
            try requireRunning()
            engine.perform(command)
            return .string("ok")
        }
    }

    static func command(_ arguments: ActionArguments) throws -> Command {
        let action = arguments.action
        guard action.hasPrefix("wm.") else { throw ProviderActionError.unknownAction(action) }
        let verb = String(action.dropFirst(3))
        var words = [verb]
        switch verb {
        case "focus", "swap", "tab", "tab-move", "display", "move-display":
            words.append(try arguments.string(0))
        case "grow":
            words.append(Self.number(try arguments.number(0)))
            words.append(Self.number(try arguments.number(1)))
        case "desktop", "send":
            words.append(Self.number(try arguments.number(0)))
        case "split", "equalize", "terminal", "group", "group-app", "float", "fullscreen", "close", "scratchpad":
            break
        default:
            throw ProviderActionError.unknownAction(action)
        }
        guard let command = Command(parsing: words.joined(separator: " ")) else {
            throw ProviderActionError.invalidArgument(action: action, message: "unsupported arguments \(words.dropFirst().joined(separator: " "))")
        }
        return command
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e9 ? String(Int(value)) : String(value)
    }

    private func running(_ action: String) -> Bool {
        guard isEngineRunning else {
            warn("\(action): the window manager is not running")
            return false
        }
        return true
    }

    private func requireRunning() throws {
        guard isEngineRunning else {
            throw ProviderActionError.unavailable(action: "wm", reason: "the window manager is not running")
        }
    }

    private var wanted: Bool { requested != toggled }

    private func reconcile() {
        if wanted && !isEngineRunning {
            lifecycle.cancel("permissions")
            guard permitted() else {
                lifecycle.once("permissions", after: Self.permissionRetry) { [weak self] in self?.reconcile() }
                return
            }
            guard engine.start(effective(settings)) else {
                lifecycle.once("permissions", after: Self.permissionRetry) { [weak self] in self?.reconcile() }
                return
            }
            isEngineRunning = true
            sentReserve = nil
            sendReserve(force: true)
            engineChanged()
        } else if !wanted {
            lifecycle.cancel("permissions")
            if isEngineRunning { halt() }
        }
    }

    private func permitted() -> Bool {
        engine.accessibilityTrusted
    }

    private func effective(_ settings: WMSettings) -> WMSettings {
        guard settings.resize == .proxy, !engine.screenRecordingAllowed else {
            proxyFallback = false
            proxyFallbackWarned = false
            return settings
        }
        proxyFallback = true
        warnProxyFallback()
        var fallback = settings
        fallback.resize = .smooth
        return fallback
    }

    private func warnProxyFallback() {
        guard proxyFallback, !proxyFallbackWarned, isRunning else { return }
        proxyFallbackWarned = true
        warn("resize-animation \"proxy\" needs screen recording; falling back to \"smooth\"")
    }

    private func halt() {
        engine.stop()
        isEngineRunning = false
        engineChanged()
    }

    private func sendReserve(force: Bool) {
        guard isEngineRunning else { return }
        let insets = WMReserve.insets(panels: panels, settings: settings, screens: engine.screens)
        guard force || insets != sentReserve else { return }
        sentReserve = insets
        engine.setReserved(insets)
    }

    private func engineChanged() {
        let state = isEngineRunning ? engine.state() : nil
        if let state {
            emitEvents(from: last, to: state)
        }
        last = state
        publishAll()
    }

    private func emitEvents(from old: WMState?, to new: WMState) {
        guard let old else { return }
        let before = Dictionary(old.windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(new.windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for window in new.windows where before[window.id] == nil {
            emit("wm.window-opened", Self.eventFields(window))
        }
        for window in old.windows where after[window.id] == nil {
            emit("wm.window-closed", Self.eventFields(window))
        }
        if old.focused != new.focused {
            emit("wm.focus-changed", new.focused.flatMap { after[$0] }.map(Self.eventFields) ?? Record([("id", .null)]))
        }
        if old.layout != new.layout {
            emit("wm.layout-changed", Record([("layout", .string(new.layout.rawValue))]))
        }
        if old.workspace != new.workspace || old.desktop != new.desktop {
            emit("wm.workspace-changed", Record([("workspace", .number(Double(new.workspace))), ("desktop", .number(Double(new.desktop)))]))
        }
    }

    private static func eventFields(_ window: WMWindowInfo) -> Record {
        Record([("id", .number(Double(window.id))), ("app", .string(window.app)), ("title", .string(window.title))])
    }

    private func publishAll() {
        guard isRunning, case .record(let record) = root() else { return }
        for key in record.keys {
            publish(key, record[key] ?? .null)
        }
    }

    private func root() -> Value {
        let state = last ?? WMState(layout: settings.layout)
        let focused = state.focused.flatMap { id in state.windows.first { $0.id == id } }
        let workspaces: Value = settings.appleDesktops || !isEngineRunning ? .list([]) : .list((1...9).map { index in
            .record(Record([
                ("index", .number(Double(index))),
                ("active", .bool(index == state.workspace)),
                ("windows", .number(Double(state.windows.filter { $0.workspace == index }.count))),
            ]))
        })
        return .record(Record([
            ("enabled", .bool(isEngineRunning)),
            ("layout", .string(state.layout.rawValue)),
            ("focused", focused.map { Self.focusedValue($0) } ?? .null),
            ("windows", Self.windowsValue(state)),
            ("desktop", .number(Double(state.desktop))),
            ("workspace", .number(Double(state.workspace))),
            ("workspaces", workspaces),
            ("tab-bars", .list(state.tabBars.map(Self.tabBarValue))),
        ]))
    }

    private static func focusedValue(_ window: WMWindowInfo) -> Value {
        .record(Record([
            ("id", .number(Double(window.id))),
            ("app", .string(window.app)),
            ("title", .string(window.title)),
            ("floating", .bool(window.floating)),
            ("group-size", .number(Double(max(1, window.group.count)))),
        ]))
    }

    static func windowsValue(_ state: WMState) -> Value {
        .list(state.windows.sorted { $0.id < $1.id }.map { window in
            var fields: [(String, Value)] = [
                ("id", .number(Double(window.id))),
                ("pid", .number(Double(window.pid))),
                ("app", .string(window.app)),
                ("bundle-id", ProviderValue.string(window.bundleID)),
                ("title", .string(window.title)),
                ("floating", .bool(window.floating)),
                ("focused", .bool(state.focused == window.id)),
                ("scratchpad", .bool(window.scratchpad)),
                ("fullscreen", .bool(window.fullscreen)),
                ("desktop", ProviderValue.number(window.desktop)),
                ("display", ProviderValue.number(window.display)),
                ("workspace", ProviderValue.number(window.workspace)),
                ("group", .list(window.group.map { .number(Double($0)) })),
            ]
            if let frame = window.frame {
                fields.append(("frame", frameValue(frame)))
            }
            return .record(Record(fields))
        })
    }

    private static func frameValue(_ frame: CGRect) -> Value {
        .record(Record([
            ("x", .number(frame.minX)), ("y", .number(frame.minY)),
            ("width", .number(frame.width)), ("height", .number(frame.height)),
        ]))
    }

    private static func tabBarValue(_ bar: WMTabBarInfo) -> Value {
        .record(Record([
            ("x", .number(bar.frame.minX)), ("y", .number(bar.frame.minY)),
            ("width", .number(bar.frame.width)), ("height", .number(bar.frame.height)),
            ("screen", .string(bar.screen)),
            ("active", .number(Double(bar.active))),
            ("tabs", .list(bar.tabs.map { tab in
                .record(Record([("window", .number(Double(tab.window))), ("title", .string(tab.title)), ("app", .string(tab.app))]))
            })),
        ]))
    }
}
