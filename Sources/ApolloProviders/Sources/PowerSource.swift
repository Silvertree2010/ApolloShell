import Foundation
import ApolloShellCore

@MainActor
public protocol PowerSource: AnyObject {
    var now: Date { get }
    var markerExists: Bool { get }
    var ruleInstalled: Bool { get }
    func takeAssertion() -> Bool
    func releaseAssertion()
    func sleepDisabled() -> Bool?
    func sudoSetSleepDisabled(_ on: Bool) -> Bool
    func askAdmin(disableSleep: Bool, installRule: Bool, _ completion: @escaping @MainActor (Bool) -> Void) -> Bool
    func cancelAdmin()
    func adminSync(disableSleep: Bool) -> Bool
    func writeMarker()
    func removeMarker()
    func removeRule(_ completion: @escaping @MainActor (Bool) -> Void)
    func battery() -> BatteryState?
}

public struct PermissionsState: Equatable, Sendable {
    public var accessibility: Bool
    public var automation: Bool?
    public var screenRecording: Bool

    public init(accessibility: Bool, automation: Bool?, screenRecording: Bool) {
        self.accessibility = accessibility
        self.automation = automation
        self.screenRecording = screenRecording
    }
}

@MainActor
public protocol PermissionsSource: AnyObject {
    var loginItem: Bool { get }
    func read() -> PermissionsState
    func requestAccessibility()
    func open(_ kind: String)
    func setLoginItem(_ on: Bool) -> Bool
}

@MainActor
public protocol ShortcutsSource: AnyObject {
    func list(_ completion: @escaping @MainActor ([UtilitiesShortcut]?) -> Void)
    func run(_ name: String, _ completion: @escaping @MainActor (Bool) -> Void)
}
