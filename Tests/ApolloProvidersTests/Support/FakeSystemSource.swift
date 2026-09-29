import ApolloShellCore
@testable import ApolloProviders

@MainActor
final class FakeSystemSource: SystemSource {
    var darkMode = false
    var darkModeFollowsSet = true
    var nightShift: Bool? = false
    var microphoneMuted: Bool? = false
    var showDesktopAvailable = true
    var accentColor = "#007AFF"
    var reduceMotion = false
    var reduceTransparency = false
    var info = SystemInfo(userName: "andrin", fullName: "Andrin", hasUserImage: true, hostName: "apollo-mbp", model: "MacBook Pro", chip: "Apple M4", macosVersion: "26.0", kernelVersion: "25.0.0")
    var uptime = 3600.0
    var appleDockHidden = false
    var hiddenFiles: Bool? = false
    var hiddenFilesSets: [Bool] = []
    var observing = false
    var commands: [SystemCommand] = []
    var pickedColor: String? = "#FF8800"
    var picks = 0
    private var handler: (@MainActor () -> Void)?

    func setDarkMode(_ on: Bool) {
        if darkModeFollowsSet { darkMode = on }
    }

    func setNightShift(_ on: Bool) -> Bool {
        guard nightShift != nil else { return false }
        nightShift = on
        return true
    }

    func setMicrophoneMuted(_ muted: Bool) -> Bool {
        guard microphoneMuted != nil else { return false }
        microphoneMuted = muted
        return true
    }

    func setAppleDockHidden(_ hidden: Bool) {
        appleDockHidden = hidden
    }

    func setHiddenFiles(_ on: Bool) {
        hiddenFilesSets.append(on)
        hiddenFiles = on
    }

    func run(_ command: SystemCommand) {
        commands.append(command)
    }

    func pickColor(_ completion: @escaping @MainActor (String?) -> Void) {
        picks += 1
        completion(pickedColor)
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        observing = true
        self.handler = handler
    }

    var polling = false

    func setPolling(_ active: Bool) {
        polling = active
    }

    func stopObserving() {
        observing = false
        handler = nil
    }

    func changed() {
        handler?()
    }
}

@MainActor
final class FakeSessionSource: SessionSource {
    var runs: [SessionAction] = []
    var locks = 0

    func run(_ action: SessionAction) {
        runs.append(action)
    }

    func lock() {
        locks += 1
    }
}
