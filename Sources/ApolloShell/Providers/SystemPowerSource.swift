import AppKit
import ApplicationServices
import IOKit.pwr_mgt
import ServiceManagement
import ApolloProviders
import ApolloShellCore

@MainActor
final class SystemPowerSource: PowerSource {
    private let marker: URL
    private let batterySource = SystemBatterySource()
    private var assertion: IOPMAssertionID?
    private var prompt: Process?

    init(directory: URL) {
        marker = directory.appendingPathComponent("lid-awake")
    }

    var now: Date { Date() }

    var markerExists: Bool { FileManager.default.fileExists(atPath: marker.path) }

    var ruleInstalled: Bool { FileManager.default.fileExists(atPath: LidAwake.sudoersFile) }

    func takeAssertion() -> Bool {
        guard assertion == nil else { return true }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "ApolloShell: keep awake" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return false }
        assertion = id
        return true
    }

    func releaseAssertion() {
        if let assertion { IOPMAssertionRelease(assertion) }
        assertion = nil
    }

    func sleepDisabled() -> Bool? {
        LidAwake.sleepDisabled(pmsetOutput: Subprocess.runAndWait(LidAwake.pmset, ["-g"])?.text ?? "")
    }

    func sudoSetSleepDisabled(_ on: Bool) -> Bool {
        Subprocess.runAndWait(LidAwake.sudo, LidAwake.sudoArguments(disableSleep: on))?.status == 0
    }

    func askAdmin(disableSleep: Bool, installRule: Bool, _ completion: @escaping @MainActor (Bool) -> Void) -> Bool {
        let arguments = LidAwake.osascriptArguments(disableSleep: disableSleep, installRuleFor: installRule ? NSUserName() : nil)
        prompt = Subprocess.launch(LidAwake.osascript, arguments) { [weak self] status in
            self?.prompt = nil
            completion(status == 0)
        }
        return prompt != nil
    }

    func cancelAdmin() {
        prompt?.terminate()
    }

    func adminSync(disableSleep: Bool) -> Bool {
        Subprocess.runAndWait(LidAwake.osascript, LidAwake.osascriptArguments(disableSleep: disableSleep))?.status == 0
    }

    func writeMarker() {
        try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: marker.path, contents: Data())
    }

    func removeMarker() {
        try? FileManager.default.removeItem(at: marker)
    }

    func removeRule(_ completion: @escaping @MainActor (Bool) -> Void) {
        let started = Subprocess.launch(LidAwake.osascript, LidAwake.removeRuleArguments()) { [weak self] _ in
            completion(!(self?.ruleInstalled ?? true))
        }
        if started == nil { completion(false) }
    }

    func battery() -> BatteryState? {
        batterySource.read().map { BatteryState(level: $0.level, charging: $0.charging, onAC: $0.onAC) }
    }
}

@MainActor
final class SystemPermissionsSource: PermissionsSource {
    private static let systemEvents = "com.apple.systemevents"

    var loginItem: Bool { SMAppService.mainApp.status == .enabled }

    func read() -> PermissionsState {
        PermissionsState(accessibility: AXIsProcessTrusted(), automation: Self.automation(), screenRecording: CGPreflightScreenCaptureAccess())
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func open(_ kind: String) {
        guard let pane = SystemSettingsPane.privacy[kind], let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    func setLoginItem(_ on: Bool) -> Bool {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            return false
        }
    }

    private static func automation() -> Bool? {
        var target = AEAddressDesc()
        let bytes = Array(systemEvents.utf8)
        guard AECreateDesc(DescType(typeApplicationBundleID), bytes, bytes.count, &target) == noErr else { return nil }
        defer { AEDisposeDesc(&target) }
        switch AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false) {
        case noErr: return true
        case OSStatus(errAEEventNotPermitted), OSStatus(errAEEventWouldRequireUserConsent): return false
        default: return nil
        }
    }
}

@MainActor
final class SystemShortcutsSource: ShortcutsSource {
    private let queue = DispatchQueue(label: AppIdentity.scoped("shortcuts"))

    func list(_ completion: @escaping @MainActor ([UtilitiesShortcut]?) -> Void) {
        queue.async {
            let result = Subprocess.runAndWait(UtilitiesShortcuts.tool, UtilitiesShortcuts.listArguments)
            let shortcuts = result.flatMap { $0.status == 0 ? UtilitiesShortcuts.parse($0.text) : nil }
            Task { @MainActor in completion(shortcuts) }
        }
    }

    func run(_ name: String, _ completion: @escaping @MainActor (Bool) -> Void) {
        let started = Subprocess.launch(UtilitiesShortcuts.tool, ["run", name]) { status in
            completion(status == 0)
        }
        if started == nil { completion(false) }
    }
}
