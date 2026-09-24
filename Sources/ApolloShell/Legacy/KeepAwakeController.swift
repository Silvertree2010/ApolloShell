import ApolloShellCore
import Foundation
import Observation
import os

@MainActor
@Observable
final class KeepAwakeController {
    private(set) var since: Date?
    private(set) var lid: KeepAwakeLid = .off

    var isOn: Bool { since != nil }

    @ObservationIgnored var onToast: (ToastText.Content) -> Void = { _ in }

    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var assertion: PowerAssertion?
    @ObservationIgnored private var lidAwakeOwned = false
    @ObservationIgnored private let lidAllowed: @MainActor () -> Bool
    @ObservationIgnored private var lidPrompt: (process: Process, disableSleep: Bool)?
    @ObservationIgnored private var batteryGuard: Timer?
    @ObservationIgnored private let log = Logger(category: "utilities")

    init(lidAllowed: @escaping @MainActor () -> Bool) {
        live = true
        self.lidAllowed = lidAllowed
        recoverLidAwake()
    }

    init(preview since: Date?) {
        live = false
        self.since = since
        lidAllowed = { false }
    }

    func set(_ on: Bool) {
        guard live, on != isOn else { return }
        if on {
            do {
                assertion = try PowerAssertion(reason: "ApolloShell: Wach halten")
                since = Date()
                reconcileLid()
                batteryGuard = .repeating(every: 60, owner: self) { $0.checkBattery() }
            } catch {
                log.error("Wach halten nicht moeglich: IOReturn \(error.code, privacy: .public)")
            }
        } else {
            assertion = nil
            since = nil
            batteryGuard?.invalidate()
            batteryGuard = nil
            reconcileLid()
        }
    }

    func shutdown() {
        guard live else { return }
        assertion = nil
        since = nil
        batteryGuard?.invalidate()
        batteryGuard = nil
        if let prompt = lidPrompt {
            if prompt.disableSleep { prompt.process.terminate() }
            return
        }
        guard lidAwakeOwned else { return }
        if Self.sudoSleepDisabled(false)
            || Subprocess.runAndWait(LidAwake.osascript, LidAwake.osascriptArguments(disableSleep: false))?.status == 0 {
            lidReleased()
        }
    }

    func lidSettingChanged() {
        guard live, isOn else { return }
        reconcileLid()
    }

    private func checkBattery() {
        guard LidAwake.shouldStop(battery: StatusModel.readBattery()) else { return }
        set(false)
        onToast(ToastText.Content(
            title: String(localized: "Keep Awake Ended"),
            message: String(localized: "Battery at \(LidAwake.batteryFloor)% – the Mac is allowed to sleep again"),
            symbol: "battery.25percent",
            kind: .warning
        ))
    }

    private var lidWanted: Bool { isOn && lidAllowed() }

    private func reconcileLid() {
        guard lidPrompt == nil else {
            lid = lidWanted ? .pending : .off
            return
        }
        if lidWanted { enableLid() } else { releaseLid() }
    }

    private func enableLid() {
        guard lid != .on else { return }
        let current = LidAwake.sleepDisabled(pmsetOutput: Self.pmsetSettings())
        if current == true {
            lidAwakeOwned = FileManager.default.fileExists(atPath: Self.lidMarker.path)
            lid = .on
            return
        }
        if Self.sudoSleepDisabled(true) {
            lidTaken()
            return
        }
        Self.writeLidMarker()
        lid = .pending
        askAdmin(disableSleep: true)
    }

    private func releaseLid() {
        guard lidAwakeOwned else {
            lid = .off
            return
        }
        if Self.sudoSleepDisabled(false) {
            lidReleased()
            return
        }
        lid = .off
        askAdmin(disableSleep: false)
    }

    private func askAdmin(disableSleep: Bool) {
        let arguments = LidAwake.osascriptArguments(
            disableSleep: disableSleep,
            installRuleFor: disableSleep ? LidAwakeRule.userToInstall : nil
        )
        let process = Subprocess.launch(LidAwake.osascript, arguments) { [weak self] status in
            self?.lidPromptFinished(disableSleep: disableSleep, ok: status == 0)
        }
        guard let process else { return lidPromptFinished(disableSleep: disableSleep, ok: false) }
        lidPrompt = (process, disableSleep)
    }

    private func lidPromptFinished(disableSleep: Bool, ok: Bool) {
        lidPrompt = nil
        if disableSleep {
            guard ok else {
                log.notice("disablesleep 1: Administrator abgelehnt, wach nur aufgeklappt")
                if !lidAwakeOwned { try? FileManager.default.removeItem(at: Self.lidMarker) }
                lid = lidWanted ? .declined : .off
                return
            }
            lidTaken()
            if !lidWanted { releaseLid() }
        } else {
            guard ok else {
                log.error("disablesleep 0: Administrator abgelehnt")
                lid = lidWanted ? .on : .off
                if !lidWanted { onToast(Self.lidStillDisabledToast) }
                return
            }
            lidReleased()
            if lidWanted { enableLid() }
        }
    }

    private func lidTaken() {
        lidAwakeOwned = true
        lid = .on
        Self.writeLidMarker()
    }

    private static func writeLidMarker() {
        let url = lidMarker
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    private func lidReleased() {
        lidAwakeOwned = false
        lid = .off
        try? FileManager.default.removeItem(at: Self.lidMarker)
    }

    private static let lidStillDisabledToast = ToastText.Content(
        title: String(localized: "Still Awake with Lid Closed"),
        message: String(localized: "Without approval, sleep stays off when closing the lid – turning Keep Awake off and on tries again"),
        symbol: "laptopcomputer",
        kind: .warning
    )

    private func recoverLidAwake() {
        guard FileManager.default.fileExists(atPath: Self.lidMarker.path) else { return }
        let current = LidAwake.sleepDisabled(pmsetOutput: Self.pmsetSettings())
        lidAwakeOwned = true
        if current == false || Self.sudoSleepDisabled(false) {
            lidReleased()
            return
        }
        askAdmin(disableSleep: false)
    }

    private static var lidMarker: URL { ShellFiles.live.lidAwakeMarker }

    private static func sudoSleepDisabled(_ on: Bool) -> Bool {
        Subprocess.runAndWait(LidAwake.sudo, LidAwake.sudoArguments(disableSleep: on))?.status == 0
    }

    private static func pmsetSettings() -> String {
        Subprocess.runAndWait(LidAwake.pmset, ["-g"])?.text ?? ""
    }
}
