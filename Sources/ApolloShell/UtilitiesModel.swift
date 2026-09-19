import AppKit
import CoreAudio
import CoreWLAN
import Foundation
import IOKit.pwr_mgt
import ApolloShellCore
import Observation
import os

/// State and actions of the Utilities panel: "Keep Awake", the sound
/// card, and the quick toggles (Wi-Fi, microphone, Bluetooth, dark mode,
/// Night Shift) along with actions (screenshot, show desktop, color
/// picker, lock, settings).
///
/// Everything without a permission dialog: IOKit assertion, CoreWLAN
/// (on/off needs no location access), CoreAudio properties (only
/// recording needs microphone permission, reading, muting, and device
/// selection do not), Bluetooth via system_profiler (see
/// `BluetoothState`), SkyLight and CoreBrightness (see UtilitiesSystem),
/// key presses via the already-granted Accessibility permission,
/// NSColorSampler.
///
/// No own recurring timer: `start()`/`stop()` call the coordinators on
/// open and close, polling only happens while it is visible.
@MainActor
@Observable
final class UtilitiesModel {
    /// "Keep Awake" with a lid part - its own state machine.
    @ObservationIgnored let keepAwakeController: KeepAwakeController
    /// Since when "Keep Awake" has been running; `nil` = off.
    var keepAwakeSince: Date? { keepAwakeController.since }
    /// State of the lid part of "Keep Awake" (`LidAwake`, pmset disablesleep).
    var lid: KeepAwakeLid { keepAwakeController.lid }
    /// `nil`: no Wi-Fi interface.
    private(set) var wifiOn: Bool?
    /// Mute state of the default input; `nil`: no input.
    private(set) var micMuted: Bool?
    private(set) var micSettable = false
    /// `nil`: not read yet or not readable.
    private(set) var bluetoothOn: Bool?
    /// `nil`: not read yet.
    private(set) var darkMode: Bool?
    /// `nil`: not available (or not read yet).
    private(set) var nightShift: Bool?
    /// "Show Desktop" shortcut enabled in Mission Control.
    private(set) var showDesktopAvailable = true

    // Sound card
    private(set) var volume: Float = 0
    private(set) var outputMuted = false
    private(set) var volumeSettable = false
    private(set) var muteSettable = false
    /// All devices unfiltered; the menus filter (ApolloShellCore).
    private(set) var audioDevices: [UtilitiesAudioDevice] = []
    private(set) var defaultOutput: UInt32?
    private(set) var defaultInput: UInt32?

    var outputs: [UtilitiesAudioDevice] { UtilitiesAudioDevices.devices(audioDevices, for: .output) }
    var inputs: [UtilitiesAudioDevice] { UtilitiesAudioDevices.devices(audioDevices, for: .input) }
    var outputLabel: String { UtilitiesAudioDevices.label(defaultID: defaultOutput, in: audioDevices) }
    var inputLabel: String { UtilitiesAudioDevices.label(defaultID: defaultInput, in: audioDevices) }

    /// For the card's toggle.
    var keepAwake: Bool {
        get { keepAwakeController.isOn }
        set { keepAwakeController.set(newValue) }
    }

    /// Every 2 s, while the panel is open: Wi-Fi (~3 ms), microphone,
    /// dark mode, Night Shift, and the audio devices are cheap. Bluetooth
    /// costs ~165 ms (its own process, not on the main thread) - so only
    /// every fifth round, i.e. every 10 s. Volume and mute come without
    /// polling via a CoreAudio listener (VolumeMonitor).
    @ObservationIgnored private static let interval: TimeInterval = 2
    @ObservationIgnored private static let bluetoothEvery = 5
    /// After the panel fades away, wait this long until macOS has handed
    /// the keyboard back to the frontmost app - only then post the key press.
    @ObservationIgnored private static let keyHandBack: Duration = .milliseconds(100)

    /// `false` for the preview: then the model reads and switches
    /// nothing, no matter which action is called.
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private let bluetooth = BluetoothState()
    @ObservationIgnored private var volumeMonitor: VolumeMonitor?
    @ObservationIgnored private var nightShiftClient: UtilitiesNightShiftClient?
    @ObservationIgnored private var nightShiftLookedUp = false
    /// Keeps the color picker alive until it delivers a color.
    @ObservationIgnored private var colorSampler: NSColorSampler?
    @ObservationIgnored private let log = Logger(category: "utilities")

    /// From the panel: close first, then `then` (see `EdgeDrawer.close(then:)`).
    @ObservationIgnored var closePanel: (_ then: @escaping @MainActor () -> Void) -> Void = { $0() }
    /// From the panel: show a brief message (color picker).
    @ObservationIgnored var onToast: (ToastText.Content) -> Void = { _ in }

    /// `lidAllowed`: whether "Keep Awake" should also apply with the lid
    /// closed - re-asked every time it is turned on, since the setting
    /// can change.
    init(lidAllowed: @escaping @MainActor () -> Bool) {
        live = true
        keepAwakeController = KeepAwakeController(lidAllowed: lidAllowed)
        keepAwakeController.onToast = { [weak self] in self?.onToast($0) }
    }

    private init(keepAwakeSince: Date?) {
        live = false
        keepAwakeController = KeepAwakeController(preview: keepAwakeSince)
    }

    /// Model with fixed state that reads and switches nothing - for
    /// previews and snapshot tests.
    static func preview(
        keepAwakeSince: Date? = nil,
        wifiOn: Bool? = true,
        micMuted: Bool? = false,
        micSettable: Bool = true,
        bluetoothOn: Bool? = true,
        darkMode: Bool? = true,
        nightShift: Bool? = false,
        showDesktopAvailable: Bool = true,
        volume: Float = 0.45,
        outputMuted: Bool = false,
        audioDevices: [UtilitiesAudioDevice] = [],
        defaultOutput: UInt32? = nil,
        defaultInput: UInt32? = nil
    ) -> UtilitiesModel {
        let model = UtilitiesModel(keepAwakeSince: keepAwakeSince)
        model.wifiOn = wifiOn
        model.micMuted = micMuted
        model.micSettable = micSettable
        model.bluetoothOn = bluetoothOn
        model.darkMode = darkMode
        model.nightShift = nightShift
        model.showDesktopAvailable = showDesktopAvailable
        model.volume = volume
        model.outputMuted = outputMuted
        model.volumeSettable = true
        model.muteSettable = true
        model.audioDevices = audioDevices
        model.defaultOutput = defaultOutput
        model.defaultInput = defaultInput
        return model
    }

    // MARK: - Polling

    func start() {
        guard live, timer == nil else { return }
        startVolume()
        refresh()
        ticks = 0
        timer = .repeating(every: Self.interval, owner: self) { $0.tick() }
    }

    /// Only stops polling. "Keep Awake" stays on - that is exactly what
    /// it is for, even with the panel closed. The volume listeners also
    /// stay: they cost nothing as long as nothing changes.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Read everything again, including Bluetooth and the show-desktop
    /// shortcut (which only changes in System Settings).
    func refresh() {
        guard live else { return }
        readWifi()
        readMicrophone()
        readBluetooth()
        readAppearance()
        readNightShift()
        readShowDesktop()
        readVolume()
        readAudioDevices()
    }

    private func tick() {
        ticks += 1
        readWifi()
        readMicrophone()
        readAppearance()
        readNightShift()
        readAudioDevices()
        if ticks % Self.bluetoothEvery == 0 { readBluetooth() }
    }

    private func readWifi() {
        let on = CWWiFiClient.shared().interface().map { $0.powerOn() }
        if on != wifiOn { wifiOn = on }
    }

    private func readMicrophone() {
        let state = Microphone.defaultInput().flatMap(Microphone.muteState(of:))
        let muted = state?.muted
        let settable = state?.settable ?? false
        if muted != micMuted { micMuted = muted }
        if settable != micSettable { micSettable = settable }
    }

    private func readBluetooth() {
        bluetooth.readOnce { [weak self] on in
            guard let self, on != self.bluetoothOn else { return }
            self.bluetoothOn = on
        }
    }

    private func readAppearance() {
        let dark = UtilitiesAppearance.isDark()
        if dark != darkMode { darkMode = dark }
    }

    /// Create the client only on first opening: loading CoreBrightness
    /// costs something, and whoever never opens the panel does not need it.
    private func readNightShift() {
        if !nightShiftLookedUp {
            nightShiftLookedUp = true
            nightShiftClient = UtilitiesNightShiftClient()
        }
        let enabled = nightShiftClient?.enabled()
        if enabled != nightShift { nightShift = enabled }
    }

    private func readShowDesktop() {
        let available = UtilitiesKeys.symbolic(id: UtilitiesHotKey.showDesktopID, fallback: .showDesktopDefault) != nil
        if available != showDesktopAvailable { showDesktopAvailable = available }
    }

    private func startVolume() {
        guard volumeMonitor == nil else { return }
        let monitor = VolumeMonitor()
        monitor.onChange = { [weak self] _, _ in self?.readVolume() }
        monitor.start()
        volumeMonitor = monitor
    }

    private func readVolume() {
        guard let monitor = volumeMonitor else { return }
        if monitor.volume != volume { volume = monitor.volume }
        if monitor.muted != outputMuted { outputMuted = monitor.muted }
        if monitor.volumeSettable != volumeSettable { volumeSettable = monitor.volumeSettable }
        if monitor.muteSettable != muteSettable { muteSettable = monitor.muteSettable }
    }

    /// Only assign what actually changed: otherwise SwiftUI rebuilds the
    /// card every 2 s, even when nothing is different.
    private func readAudioDevices() {
        let devices = UtilitiesAudioHardware.devices()
        if devices != audioDevices { audioDevices = devices }
        let output = UtilitiesAudioHardware.defaultDevice(.output)
        if output != defaultOutput { defaultOutput = output }
        let input = UtilitiesAudioHardware.defaultDevice(.input)
        if input != defaultInput { defaultInput = input }
    }

    // MARK: - Actions

    /// When the app quits: leave nothing awake.
    func shutdown() {
        keepAwakeController.shutdown()
    }

    /// Nexus toggled "Also with the lid closed".
    func lidSettingChanged() {
        keepAwakeController.lidSettingChanged()
    }

    func toggleWifi() {
        guard live, let interface = CWWiFiClient.shared().interface() else { return }
        let target = !interface.powerOn()
        do {
            try interface.setPower(target)
        } catch {
            log.error("Failed to toggle Wi-Fi: \(error.localizedDescription, privacy: .public)")
        }
        readWifi()
    }

    func toggleMicMute() {
        guard live,
              let device = Microphone.defaultInput(),
              let state = Microphone.muteState(of: device), state.settable
        else { return }
        let status = Microphone.setMuted(!state.muted, device: device)
        if status != noErr {
            log.error("Failed to mute microphone: OSStatus \(status, privacy: .public)")
        }
        readMicrophone()
    }

    /// Toggling Bluetooth itself would only work via private APIs; the
    /// button therefore leads straight into Settings (pane measured:
    /// Bluetooth.appex reports com.apple.BluetoothSettings).
    func openBluetoothSettings() {
        guard live, let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The panel stays open: it recolors along with the change, that is
    /// the confirmation. Switch immediately (SkyLight reports nothing
    /// back), read the real state again after half a second.
    func toggleDarkMode() {
        guard live, let current = darkMode else { return }
        UtilitiesAppearance.setDark(!current)
        darkMode = !current
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.readAppearance()
        }
    }

    func toggleNightShift() {
        guard live, let client = nightShiftClient, let current = nightShift else { return }
        if !client.setEnabled(!current) {
            log.error("Failed to toggle Night Shift")
        }
        readNightShift()
    }

    /// Apple's toolbar for screenshots and recording (Cmd-Shift-5, or
    /// whatever is set under Keyboard Shortcuts). If the shortcut is off
    /// or the permission is missing, the same toolbar via Screenshot.app.
    func takeScreenshot() {
        guard live else { return }
        let key = UtilitiesKeys.symbolic(id: UtilitiesHotKey.screenshotToolbarID, fallback: .screenshotToolbarDefault)
        closePanel {
            if let key, UtilitiesKeys.post(key) { return }
            let app = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func showDesktop() {
        guard live, let key = UtilitiesKeys.symbolic(id: UtilitiesHotKey.showDesktopID, fallback: .showDesktopDefault)
        else { return }
        postAfterClose(key)
    }

    /// Ctrl-Cmd-Q goes to the frontmost app (Apple menu) - so the panel
    /// must be gone beforehand, otherwise our panel would receive it.
    func lockScreen() {
        guard live else { return }
        postAfterClose(.lockScreen)
    }

    private func postAfterClose(_ key: UtilitiesHotKey) {
        closePanel {
            Task { @MainActor in
                try? await Task.sleep(for: Self.keyHandBack)
                UtilitiesKeys.post(key)
            }
        }
    }

    /// Apple's color picker (NSColorSampler, public, no permission
    /// needed). Panel gone first, so the spot underneath can be hit too.
    func pickColor() {
        guard live else { return }
        closePanel { [weak self] in
            guard let self else { return }
            let sampler = NSColorSampler()
            colorSampler = sampler
            sampler.show { color in
                // In sRGB like on the web and in Figma; no color (Esc) is nil.
                let hex = color?.usingColorSpace(.sRGB).map {
                    UtilitiesColorHex.hex(red: Double($0.redComponent), green: Double($0.greenComponent),
                                          blue: Double($0.blueComponent))
                }
                // Kept strong until chosen: the model lives as long as the
                // app anyway.
                Task { @MainActor in self.colorPicked(hex) }
            }
        }
    }

    private func colorPicked(_ hex: String?) {
        colorSampler = nil
        guard let hex else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(hex, forType: .string)
        onToast(ToastText.colorCopied(hex))
    }

    // MARK: - New actions and custom buttons

    /// `pmset displaysleepnow`: only turns the screens off, the Mac
    /// keeps running (downloads, music). Needs no sudo. Panel gone
    /// first - otherwise it would still be half there when waking up.
    func sleepDisplay() {
        guard live else { return }
        closePanel { Subprocess.launch("/usr/bin/pmset", ["displaysleepnow"]) }
    }

    /// Hide every normal app (`NSRunningApplication.hide`, public, no
    /// permission needed) - never the shell itself, otherwise the bar
    /// and panels would disappear too. The rule lives in `UtilitiesHideApps`.
    func hideApps(_ options: UtilitiesHideAppsOptions) {
        guard live else { return }
        closePanel {
            let own = ProcessInfo.processInfo.processIdentifier
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            for app in NSWorkspace.shared.runningApplications where UtilitiesHideApps.shouldHide(
                pid: app.processIdentifier, isRegular: app.activationPolicy == .regular, ownPID: own,
                frontmostPID: front, keepFrontmost: options.keepFrontmost
            ) {
                app.hide()
            }
        }
    }

    /// Like a click in the Dock (`BarApps.open`). Panel closed first: the
    /// app comes to the front, and the panel should not sit on top of it.
    func openApp(_ options: UtilitiesAppOptions) {
        let bundleID = options.bundleID.trimmingCharacters(in: .whitespaces)
        guard live, !bundleID.isEmpty else { return }
        closePanel { BarApps.open(bundleID) }
    }

    /// In the default app for the address (browser, mail, ...).
    func openLink(_ options: UtilitiesLinkOptions) {
        guard live, let url = UtilitiesLink.url(from: options.url) else { return }
        closePanel { NSWorkspace.shared.open(url) }
    }

    /// `shortcuts run` as its own process, without waiting for it: a
    /// shortcut can run for seconds or prompt for input. If it ends with
    /// an error, a toast reports it - otherwise a click with no effect
    /// would be a mystery. This is how, for example, a Focus is toggled
    /// without private APIs.
    func runShortcut(_ options: UtilitiesShortcutOptions) {
        guard live, let arguments = UtilitiesShortcuts.runArguments(options) else { return }
        let name = options.title.isEmpty ? options.name : options.title
        closePanel { [weak self] in
            let failed: @MainActor (Int32) -> Void = { status in
                self?.log.error("Shortcut failed: status \(status, privacy: .public)")
                self?.onToast(ToastText.shortcutFailed(name))
            }
            let started = Subprocess.launch(UtilitiesShortcuts.tool, arguments) { status in
                if status != 0 { failed(status) }
            }
            if started == nil { failed(-1) }
        }
    }

    // MARK: - Sound

    /// While dragging the slider. Show it immediately, the listener
    /// confirms. Above 0 it lifts mute (VolumeMonitor.setVolume, like
    /// the keys).
    func setVolume(_ value: Float) {
        guard live, volumeSettable, let monitor = volumeMonitor else { return }
        let clamped = min(max(value, 0), 1)
        monitor.setVolume(clamped)
        volume = clamped
        if clamped > 0 { outputMuted = false }
    }

    func toggleOutputMute() {
        guard live, muteSettable, let monitor = volumeMonitor else { return }
        monitor.setMuted(!outputMuted)
        readVolume()
    }

    func selectDevice(_ device: UInt32, scope: UtilitiesAudioScope) {
        guard live else { return }
        let status = UtilitiesAudioHardware.setDefault(device, scope)
        if status != noErr {
            log.error("Failed to select audio device: OSStatus \(status, privacy: .public)")
        }
        readAudioDevices()
        readVolume()
    }

    /// Sets the panel: opens Nexus (Caelestia's "Settings" button opens
    /// its own settings window). System Settings is one line away from there.
    @ObservationIgnored var onOpenSettings: () -> Void = {}

    func openSettings() {
        guard live else { return }
        onOpenSettings()
    }
}

/// An IOKit power assertion "no idle sleep" (like `caffeinate -i`: the
/// Mac stays awake, the screen may still turn off).
///
/// Lives exactly as long as this object. So it cannot get stuck: turning
/// it off, the model disappearing, the app quitting - it goes away every
/// time (when quitting, macOS clears the process's assertions anyway).
final class PowerAssertion {
    struct Failure: Error {
        let code: IOReturn
    }

    private let id: IOPMAssertionID

    init(reason: String) throws(Failure) {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { throw Failure(code: result) }
        self.id = id
    }

    deinit {
        IOPMAssertionRelease(id)
    }
}

/// Mute state of the default input via CoreAudio.
///
/// Only reads and sets properties, no audio - hence no microphone
/// permission needed. Measured 09/14: the built-in "MacBook Pro
/// Microphone" has the property on the main element and it is settable.
/// Other devices (USB, Bluetooth) may lack it; then `nil` or not
/// settable, and the button is off.
enum Microphone {
    static func defaultInput() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func muteState(of device: AudioObjectID) -> (muted: Bool, settable: Bool)? {
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        var settable: DarwinBoolean = false
        let settableStatus = AudioObjectIsPropertySettable(device, &address, &settable)
        return (value != 0, settableStatus == noErr && settable.boolValue)
    }

    static func setMuted(_ muted: Bool, device: AudioObjectID) -> OSStatus {
        var address = muteAddress
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
