import Foundation
import ApolloWMCore
@testable import ApolloProviders

@MainActor
final class FakeWMEngine: WMEngine {
    var accessibilityTrusted = true
    var screenRecordingAllowed = true
    var screens = [WMScreen(key: "Built-in 1512x982", isMain: true), WMScreen(key: "LG 2560x1440", isMain: false)]
    var onChange: (@MainActor () -> Void)?
    var current = WMState()
    var startAccepts = true
    private(set) var starts: [WMSettings] = []
    private(set) var configures: [WMSettings] = []
    private(set) var stops = 0
    private(set) var commands: [Command] = []
    private(set) var layouts: [WMSettings.Layout] = []
    private(set) var focusedWindows: [UInt32] = []
    private(set) var reserved: [[String: WMInsets]] = []

    func start(_ settings: WMSettings) -> Bool {
        starts.append(settings)
        current.layout = settings.layout
        return startAccepts
    }

    func configure(_ settings: WMSettings) { configures.append(settings) }
    func stop() { stops += 1 }
    func perform(_ command: Command) { commands.append(command) }

    func setLayout(_ layout: WMSettings.Layout) {
        layouts.append(layout)
        current.layout = layout
    }

    func focusWindow(_ id: UInt32) -> Bool {
        guard current.windows.contains(where: { $0.id == id }) else { return false }
        focusedWindows.append(id)
        return true
    }

    func setReserved(_ insets: [String: WMInsets]) { reserved.append(insets) }
    func state() -> WMState { current }

    func change(_ update: (inout WMState) -> Void) {
        update(&current)
        onChange?()
    }
}
