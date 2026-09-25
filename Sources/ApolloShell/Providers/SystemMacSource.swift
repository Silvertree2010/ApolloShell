import AppKit
import ApolloProviders
import ApolloShellCore
import CoreAudio
import IOKit
import os

@MainActor
final class SystemMacSource: SystemSource {
    private static let pollInterval: TimeInterval = 2

    private let dock: AppleDockHidingController
    private var nightShiftClient: UtilitiesNightShiftClient?
    private var nightShiftLookedUp = false
    private var colorSampler: NSColorSampler?
    private var handler: (@MainActor () -> Void)?
    private var distributed: [NSObjectProtocol] = []
    private var local: [NSObjectProtocol] = []
    private var workspace: [NSObjectProtocol] = []
    private var poll: Timer?
    private lazy var cachedInfo = Self.readInfo()

    init(directory: URL) {
        dock = AppleDockHidingController(fileURL: directory.appendingPathComponent("apple-dock.json"))
    }

    var darkMode: Bool { UtilitiesAppearance.isDark() }

    var nightShift: Bool? {
        if !nightShiftLookedUp {
            nightShiftLookedUp = true
            nightShiftClient = UtilitiesNightShiftClient()
        }
        return nightShiftClient?.enabled()
    }

    var microphoneMuted: Bool? {
        guard let device = Microphone.defaultInput(), let state = Microphone.muteState(of: device), state.settable else { return nil }
        return state.muted
    }

    var showDesktopAvailable: Bool {
        UtilitiesKeys.symbolic(id: UtilitiesHotKey.showDesktopID, fallback: .showDesktopDefault) != nil
    }

    var accentColor: String {
        guard let color = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return "#007AFF" }
        return UtilitiesColorHex.hex(red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent))
    }

    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var reduceTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }

    var info: SystemInfo { cachedInfo }

    var uptime: Double { ProcessInfo.processInfo.systemUptime }

    var appleDockHidden: Bool { dock.isHidden }

    func setDarkMode(_ on: Bool) {
        UtilitiesAppearance.setDark(on)
    }

    func setNightShift(_ on: Bool) -> Bool {
        _ = nightShift
        return nightShiftClient?.setEnabled(on) ?? false
    }

    func setMicrophoneMuted(_ muted: Bool) -> Bool {
        guard let device = Microphone.defaultInput(), let state = Microphone.muteState(of: device), state.settable else { return false }
        return Microphone.setMuted(muted, device: device) == noErr
    }

    func setAppleDockHidden(_ hidden: Bool) {
        dock.apply(hidden)
    }

    func terminate() {
        dock.terminate()
    }

    func run(_ command: SystemCommand) {
        switch command {
        case .screenshot:
            let key = UtilitiesKeys.symbolic(id: UtilitiesHotKey.screenshotToolbarID, fallback: .screenshotToolbarDefault)
            if let key, UtilitiesKeys.post(key) { return }
            let app = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        case .showDesktop:
            if let key = UtilitiesKeys.symbolic(id: UtilitiesHotKey.showDesktopID, fallback: .showDesktopDefault) {
                UtilitiesKeys.post(key)
            }
        case .lock:
            UtilitiesKeys.post(.lockScreen)
        case .displaySleep:
            Subprocess.launch("/usr/bin/pmset", ["displaysleepnow"])
        case .hideApps(let keepFrontmost):
            let own = ProcessInfo.processInfo.processIdentifier
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            for app in NSWorkspace.shared.runningApplications where UtilitiesHideApps.shouldHide(
                pid: app.processIdentifier, isRegular: app.activationPolicy == .regular, ownPID: own,
                frontmostPID: front, keepFrontmost: keepFrontmost
            ) {
                app.hide()
            }
        case .openSettings(let pane):
            if let pane, let url = URL(string: "x-apple.systempreferences:\(pane)") {
                NSWorkspace.shared.open(url)
                return
            }
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return }
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        }
    }

    func pickColor(_ completion: @escaping @MainActor (String?) -> Void) {
        let sampler = NSColorSampler()
        colorSampler = sampler
        sampler.show { [weak self] color in
            let hex = color?.usingColorSpace(.sRGB).map {
                UtilitiesColorHex.hex(red: Double($0.redComponent), green: Double($0.greenComponent), blue: Double($0.blueComponent))
            }
            Task { @MainActor in
                self?.colorSampler = nil
                if let hex {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(hex, forType: .string)
                }
                completion(hex)
            }
        }
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        stopObserving()
        self.handler = handler
        let notify: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.handler?() }
        }
        distributed.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main, using: notify))
        local.append(NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main, using: notify))
        workspace.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main, using: notify))
    }

    func setPolling(_ active: Bool) {
        guard active, handler != nil else {
            poll?.invalidate()
            poll = nil
            return
        }
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handler?() }
        }
    }

    func stopObserving() {
        for observer in distributed { DistributedNotificationCenter.default().removeObserver(observer) }
        for observer in local { NotificationCenter.default.removeObserver(observer) }
        for observer in workspace { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        distributed.removeAll()
        local.removeAll()
        workspace.removeAll()
        poll?.invalidate()
        poll = nil
        handler = nil
    }

    private static func readInfo() -> SystemInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return SystemInfo(
            userName: NSUserName(),
            fullName: NSFullUserName(),
            hasUserImage: userImageExists(),
            hostName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            model: productName() ?? sysctl("hw.model") ?? "Mac",
            chip: sysctl("machdep.cpu.brand_string") ?? "",
            macosVersion: version.patchVersion == 0 ? "\(version.majorVersion).\(version.minorVersion)" : "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            kernelVersion: sysctl("kern.osrelease") ?? ""
        )
    }

    func userImageData() -> Data? {
        guard let result = Subprocess.runAndWait("/usr/bin/dscl", [".", "-read", "/Users/\(NSUserName())", "JPEGPhoto"]), result.status == 0 else { return nil }
        return Self.photoData(String(decoding: result.output, as: UTF8.self))
    }

    static func photoData(_ output: String) -> Data? {
        guard let range = output.range(of: "JPEGPhoto:"), output.hasPrefix("JPEGPhoto:") else { return nil }
        let hex = output[range.upperBound...].filter(\.isHexDigit)
        guard !hex.isEmpty, hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    private static func userImageExists() -> Bool {
        let result = Subprocess.runAndWait("/usr/bin/dscl", [".", "-read", "/Users/\(NSUserName())", "JPEGPhoto"])
        return result?.status == 0 && !(result?.output.isEmpty ?? true)
    }

    private static func productName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data else { return nil }
        let name = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
        return name.isEmpty ? nil : name
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
}

@MainActor
final class SystemSessionSource: SessionSource {
    func run(_ action: SessionAction) {
        let command = action.command
        Subprocess.launch(command.executable, command.arguments)
    }

    func lock() {
        UtilitiesKeys.post(.lockScreen)
    }
}

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
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    }
}
