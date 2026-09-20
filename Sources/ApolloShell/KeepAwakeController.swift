import ApolloShellCore
import Foundation
import Observation
import os

/// "Keep Awake": the IOKit assertion, the battery guard and the lid part
/// (`pmset disablesleep`, see `LidAwake`) together with the administrator
/// prompt and the marker for the crash case.
///
/// A state machine of its own; the utilities model only passes things on.
@MainActor
@Observable
final class KeepAwakeController {
    /// Since when "Keep Awake" has been running; `nil` = off.
    private(set) var since: Date?
    /// State of the lid part.
    private(set) var lid: KeepAwakeLid = .off

    var isOn: Bool { since != nil }

    /// Show a toast (battery guard, a refused permission).
    @ObservationIgnored var onToast: (ToastText.Content) -> Void = { _ in }

    /// `false` for previews: switches nothing.
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var assertion: PowerAssertion?
    /// Did the app set `disablesleep` itself? Only then does it put it back.
    /// If it stood at 1 before already (from somebody else), it stays the way
    /// it was.
    @ObservationIgnored private var lidAwakeOwned = false
    /// The setting "With the lid closed too" (settings.json keepAwake). It is
    /// asked for on every switch-on, since it can change.
    @ObservationIgnored private let lidAllowed: @MainActor () -> Bool
    /// The osascript process of the open administrator prompt and what it is
    /// for. While it runs, no second prompt; afterwards things are matched up.
    /// When the app ends, a switch-on prompt is cancelled.
    @ObservationIgnored private var lidPrompt: (process: Process, disableSleep: Bool)?
    /// Battery guard while Keep Awake runs: look every minute.
    @ObservationIgnored private var batteryGuard: Timer?
    @ObservationIgnored private let log = Logger(category: "utilities")

    init(lidAllowed: @escaping @MainActor () -> Bool) {
        live = true
        self.lidAllowed = lidAllowed
        recoverLidAwake()
    }

    /// A fixed state for previews and image samples.
    init(preview since: Date?) {
        live = false
        self.since = since
        lidAllowed = { false }
    }

    func set(_ on: Bool) {
        guard live, on != isOn else { return }
        if on {
            do {
                assertion = try PowerAssertion(reason: "ApolloShell: Keep Awake")
                since = Date()
                reconcileLid()
                batteryGuard = .repeating(every: 60, owner: self) { $0.checkBattery() }
            } catch {
                log.error("Keep Awake not possible: IOReturn \(error.code, privacy: .public)")
            }
        } else {
            // Letting go = the object is gone, see PowerAssertion.deinit.
            assertion = nil
            since = nil
            batteryGuard?.invalidate()
            batteryGuard = nil
            reconcileLid()
        }
    }

    /// When the app ends: leave nothing awake. If putting it back needs an
    /// administrator, the answer is waited for here - afterwards the app is no
    /// longer alive to pick it up, and a closed Mac in a bag would never
    /// sleep.
    ///
    /// When an administrator prompt is open right now, there is no waiting: a
    /// switch-on prompt is cancelled, a switch-off prompt stays standing. The
    /// marker lies there in both cases, and the next start matches up.
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
        // This is where it waits (see above) - on an administrator prompt too.
        if Self.sudoSleepDisabled(false)
            || Subprocess.runAndWait(LidAwake.osascript, LidAwake.osascriptArguments(disableSleep: false))?.status == 0 {
            lidReleased()
        }
    }

    /// Nexus toggled "With the lid closed too": it takes hold right away,
    /// while "Keep Awake" is running as well.
    func lidSettingChanged() {
        guard live, isOn else { return }
        reconcileLid()
    }

    /// Off at 10 % on battery - and say why.
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

    // MARK: Awake with the lid closed (pmset disablesleep, see LidAwake)

    /// Should the lid part hold right now?
    private var lidWanted: Bool { isOn && lidAllowed() }

    /// Brings the lid part to the wanted state. While an administrator prompt
    /// is still running, wait for its answer first - `lidPromptFinished`
    /// matches up again afterwards.
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
            // On already. If our marker still lies there (a reset was
            // refused), it is ours - otherwise somebody else set it and it
            // stays the way it was afterwards.
            lidAwakeOwned = FileManager.default.fileExists(atPath: Self.lidMarker.path)
            lid = .on
            return
        }
        if Self.sudoSleepDisabled(true) {
            lidTaken()
            return
        }
        // No password-free sudo: macOS asks for an administrator.
        // The marker beforehand: should the app end before the answer arrives
        // and it is agreed to after all, the next start puts it back.
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
        // On the first switch-on the same prompt creates the rule without a
        // password; after that `sudo -n` works and nobody is asked again.
        let arguments = LidAwake.osascriptArguments(
            disableSleep: disableSleep,
            installRuleFor: disableSleep ? LidAwakeRule.userToInstall : nil
        )
        let process = Subprocess.launch(LidAwake.osascript, arguments) { [weak self] status in
            self?.lidPromptFinished(disableSleep: disableSleep, ok: status == 0)
        }
        // If osascript could not be started, that counts as a refusal.
        guard let process else { return lidPromptFinished(disableSleep: disableSleep, ok: false) }
        lidPrompt = (process, disableSleep)
    }

    /// The answer to the administrator prompt. When it is cancelled, osascript
    /// hands back an error (-128); then "Keep Awake" runs without the lid part.
    private func lidPromptFinished(disableSleep: Bool, ok: Bool) {
        lidPrompt = nil
        if disableSleep {
            guard ok else {
                log.notice("disablesleep 1: administrator refused, awake only with the lid open")
                // The marker put down beforehand no longer holds.
                if !lidAwakeOwned { try? FileManager.default.removeItem(at: Self.lidMarker) }
                lid = lidWanted ? .declined : .off
                return
            }
            lidTaken()
            // Switched off during the prompt: put it back right away.
            if !lidWanted { releaseLid() }
        } else {
            guard ok else {
                // The marker stays: the next start (or the next off) tries
                // again. And say that the Mac stays awake for now.
                log.error("disablesleep 0: administrator refused")
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
        // The marker for the crash case, see recoverLidAwake().
        Self.writeLidMarker()
    }

    /// The folder may still be missing on a fresh installation.
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

    /// If the app crashed while it had `disablesleep` set, the Mac would never
    /// sleep again - with the lid closed in a bag as well. So clean up on the
    /// next start when the marker is still there. If it stands at 0 anyway by
    /// now, deleting the marker is enough.
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

    // Both tools run synchronously on the main thread: measured, it is
    // milliseconds, and the state machine stays without in-between states.

    /// `sudo -n`: without a password or not at all - never waits for input.
    private static func sudoSleepDisabled(_ on: Bool) -> Bool {
        Subprocess.runAndWait(LidAwake.sudo, LidAwake.sudoArguments(disableSleep: on))?.status == 0
    }

    /// `pmset -g`, the active settings.
    private static func pmsetSettings() -> String {
        Subprocess.runAndWait(LidAwake.pmset, ["-g"])?.text ?? ""
    }
}
