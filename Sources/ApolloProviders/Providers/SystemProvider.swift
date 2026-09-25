import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class SystemProvider: BaseProvider {
    static let darkModeReread: Double = 0.5
    static let uptimeInterval: Double = 60

    private let source: any SystemSource
    private var lastDark: Bool?

    public init(source: any SystemSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("system"), clock: clock)
    }

    private var userImage: (id: String, data: Data?)?

    public func userImageData(_ id: String) -> Data? {
        guard id == source.info.userName else { return nil }
        if let userImage, userImage.id == id { return userImage.data }
        let data = source.userImageData()
        userImage = (id, data)
        return data
    }

    override func didStart() {
        lastDark = nil
        userImage = nil
        source.observeChanges { [weak self] in
            self?.refresh()
        }
        let info = source.info
        publish("user-name", .string(info.userName))
        publish("full-name", .string(info.fullName))
        publish("user-image", info.hasUserImage ? .image(ImageRef(source: "user-image", id: info.userName)) : .null)
        publish("host-name", .string(info.hostName))
        publish("model", .string(info.model))
        publish("chip", .string(info.chip))
        publish("macos-version", .string(info.macosVersion))
        publish("kernel-version", .string(info.kernelVersion))
        refresh()
    }

    static let polledFields = ["night-shift", "microphone-muted", "show-desktop-available", "apple-dock-hidden"]

    override func didChangeDemand() {
        source.setPolling(demand.wantsAny(Self.polledFields))
        timers.set("uptime", every: Self.uptimeInterval, active: demand.wants("uptime"), immediately: true) { [weak self] in
            guard let self else { return }
            self.publish("uptime", ProviderValue.number(self.source.uptime))
        }
    }

    override func didStop() {
        source.stopObserving()
        lastDark = nil
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        switch arguments.action {
        case "system.set-dark-mode":
            setDark(try arguments.bool(0))
        case "system.toggle-dark-mode":
            setDark(!(lastDark ?? source.darkMode))
        case "system.set-night-shift":
            setNightShift(try arguments.bool(0))
        case "system.toggle-night-shift":
            guard let current = source.nightShift else {
                warn("system.toggle-night-shift: Night Shift is not available")
                return .null
            }
            setNightShift(!current)
        case "system.set-microphone-muted":
            setMicrophone(try arguments.bool(0))
        case "system.toggle-microphone":
            guard let current = source.microphoneMuted else {
                warn("system.toggle-microphone: no input device that can be muted")
                return .null
            }
            setMicrophone(!current)
        case "system.hide-apple-dock":
            source.setAppleDockHidden(try arguments.bool(0))
            refresh()
        case "system.screenshot":
            source.run(.screenshot)
        case "system.show-desktop":
            source.run(.showDesktop)
        case "system.lock":
            source.run(.lock)
        case "system.display-sleep":
            source.run(.displaySleep)
        case "system.hide-apps":
            source.run(.hideApps(keepFrontmost: try Self.keepFrontmost(arguments)))
        case "system.open-settings":
            source.run(.openSettings(try Self.pane(arguments)))
        case "system.color-picker":
            source.pickColor { [weak self] hex in
                guard let hex else { return }
                self?.emit("system.color-copied", Record([("hex", .string(hex))]))
            }
        default:
            throw ProviderActionError.unknownAction(arguments.action)
        }
        return .null
    }

    private func setDark(_ dark: Bool) {
        source.setDarkMode(dark)
        applyDark(dark)
        timers.once("dark-reread", after: Self.darkModeReread) { [weak self] in
            self?.refresh()
        }
    }

    private func setNightShift(_ on: Bool) {
        if !source.setNightShift(on) { warn("system.set-night-shift: Night Shift could not be switched") }
        refresh()
    }

    private func setMicrophone(_ muted: Bool) {
        if !source.setMicrophoneMuted(muted) { warn("system.set-microphone-muted: the input device could not be muted") }
        refresh()
    }

    private func applyDark(_ dark: Bool) {
        publish("dark-mode", .bool(dark))
        if let lastDark, lastDark != dark, isRunning {
            emit("system.appearance-changed")
        }
        if isRunning { lastDark = dark }
    }

    private func refresh() {
        guard isRunning else { return }
        applyDark(source.darkMode)
        publish("night-shift", ProviderValue.bool(source.nightShift))
        publish("microphone-muted", ProviderValue.bool(source.microphoneMuted))
        publish("show-desktop-available", .bool(source.showDesktopAvailable))
        publish("accent-color", .string(source.accentColor))
        publish("reduce-motion", .bool(source.reduceMotion))
        publish("reduce-transparency", .bool(source.reduceTransparency))
        publish("apple-dock-hidden", .bool(source.appleDockHidden))
    }

    static func keepFrontmost(_ arguments: ActionArguments) throws -> Bool {
        if let property = arguments.property("keep-frontmost") {
            guard case .bool(let flag) = property else {
                throw ProviderActionError.invalidArgument(action: arguments.action, message: "keep-frontmost must be a bool")
            }
            return flag
        }
        return arguments.values.isEmpty ? false : try arguments.bool(0)
    }

    static func pane(_ arguments: ActionArguments) throws -> String? {
        guard !arguments.values.isEmpty, arguments.values[0] != .null else { return nil }
        let pane = try arguments.string(0)
        guard let identifier = SystemSettingsPane.identifier(pane) else {
            throw ProviderActionError.invalidArgument(action: arguments.action, message: "unknown settings pane \"\(pane)\"")
        }
        return identifier
    }
}

@MainActor
public final class SessionProvider: BaseProvider {
    private let source: any SessionSource

    public init(source: any SessionSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("session"), clock: clock)
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        switch arguments.action {
        case "session.logout": source.run(.logOut)
        case "session.restart": source.run(.restart)
        case "session.shutdown": source.run(.shutDown)
        case "session.sleep": source.run(.sleep)
        case "session.lock": source.lock()
        default: throw ProviderActionError.unknownAction(arguments.action)
        }
        return .null
    }
}
