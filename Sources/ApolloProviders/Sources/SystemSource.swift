import Foundation
import ApolloShellCore

public struct SystemInfo: Equatable, Sendable {
    public var userName: String
    public var fullName: String
    public var hasUserImage: Bool
    public var hostName: String
    public var model: String
    public var chip: String
    public var macosVersion: String
    public var kernelVersion: String

    public init(userName: String, fullName: String, hasUserImage: Bool, hostName: String, model: String, chip: String, macosVersion: String, kernelVersion: String) {
        self.userName = userName
        self.fullName = fullName
        self.hasUserImage = hasUserImage
        self.hostName = hostName
        self.model = model
        self.chip = chip
        self.macosVersion = macosVersion
        self.kernelVersion = kernelVersion
    }
}

public enum SystemCommand: Equatable, Sendable {
    case screenshot
    case showDesktop
    case lock
    case displaySleep
    case hideApps(keepFrontmost: Bool)
    case openSettings(String?)
}

@MainActor
public protocol SystemSource: AnyObject {
    var darkMode: Bool { get }
    var nightShift: Bool? { get }
    var microphoneMuted: Bool? { get }
    var showDesktopAvailable: Bool { get }
    var accentColor: String { get }
    var reduceMotion: Bool { get }
    var reduceTransparency: Bool { get }
    var info: SystemInfo { get }
    var uptime: Double { get }
    var appleDockHidden: Bool { get }
    func setDarkMode(_ on: Bool)
    func setNightShift(_ on: Bool) -> Bool
    func setMicrophoneMuted(_ muted: Bool) -> Bool
    func setAppleDockHidden(_ hidden: Bool)
    var appleMenuBarHidden: Bool { get }
    func setAppleMenuBarHidden(_ hidden: Bool)
    func run(_ command: SystemCommand)
    func pickColor(_ completion: @escaping @MainActor (String?) -> Void)
    func observeChanges(_ handler: @escaping @MainActor () -> Void)
    func setPolling(_ active: Bool)
    func stopObserving()
    func userImageData() -> Data?
}

extension SystemSource {
    public func userImageData() -> Data? { nil }
    public var appleMenuBarHidden: Bool { false }
    public func setAppleMenuBarHidden(_ hidden: Bool) {}
}

@MainActor
public protocol SessionSource: AnyObject {
    func run(_ action: SessionAction)
    func lock()
}

public enum SystemSettingsPane {
    public static let identifiers: [String: String] = [
        "wallpaper": "com.apple.Wallpaper-Settings.extension",
        "appearance": "com.apple.Appearance-Settings.extension",
        "network": "com.apple.Network-Settings.extension",
        "wifi": "com.apple.wifi-settings-extension",
        "bluetooth": "com.apple.BluetoothSettings",
        "sound": "com.apple.Sound-Settings.extension",
        "battery": "com.apple.Battery-Settings.extension",
        "notifications": "com.apple.Notifications-Settings.extension",
        "software-update": "com.apple.Software-Update-Settings.extension",
        "language-region": "com.apple.Localization-Settings.extension",
        "accessibility": "com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        "login-items": "com.apple.LoginItems-Settings.extension",
        "about": "com.apple.SystemProfiler.AboutExtension",
    ]

    public static let privacy: [String: String] = [
        "accessibility": "com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        "automation": "com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
        "screen-recording": "com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
    ]

    public static func identifier(_ pane: String) -> String? {
        identifiers[pane]
    }
}

public extension SystemSource {
    func setPolling(_ active: Bool) {}
}
