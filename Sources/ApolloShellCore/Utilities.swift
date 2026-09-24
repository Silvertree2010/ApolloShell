import Foundation

public enum KeepAwakeText {
    public static let title = String(localized: "Keep Awake")
    public static let inactive = String(localized: "Mac sleeps normally")

    public static func subtitle(since: Date?, now: Date, lidClosed: Bool = false, calendar: Calendar = .current) -> String {
        subtitle(since: since, now: now, lid: lidClosed ? .on : .off, calendar: calendar)
    }

    public static func subtitle(since: Date?, now: Date, lid: KeepAwakeLid, calendar: Calendar = .current) -> String {
        guard let since else { return inactive }
        let base = plainSubtitle(since: since, now: now, calendar: calendar)
        switch lid {
        case .off: return base
        case .on: return base + String(localized: " · also with lid closed")
        case .pending: return base + String(localized: " · waiting for approval")
        case .declined: return base + String(localized: " · only with lid open")
        }
    }

    private static func plainSubtitle(since: Date, now: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.day, .month, .hour, .minute], from: since)
        let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        if calendar.isDate(since, inSameDayAs: now) {
            return String(localized: "Active since \(time)")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(since, inSameDayAs: yesterday) {
            return String(localized: "Active since yesterday, \(time)")
        }
        return String(localized: "Active since \(String(format: "%02d.%02d.", c.day ?? 0, c.month ?? 0)), ") + time
    }
}

public struct QuickToggleLook: Equatable, Sendable {
    public var symbol: String?
    public var active: Bool
    public var enabled: Bool
    public var help: String

    public init(symbol: String?, active: Bool, enabled: Bool, help: String) {
        self.symbol = symbol
        self.active = active
        self.enabled = enabled
        self.help = help
    }
}

public enum QuickToggles {
    public static func wifi(powerOn: Bool?) -> QuickToggleLook {
        switch powerOn {
        case true?: QuickToggleLook(symbol: "wifi", active: true, enabled: true, help: String(localized: "Wi-Fi On"))
        case false?: QuickToggleLook(symbol: "wifi.slash", active: false, enabled: true, help: String(localized: "Wi-Fi Off"))
        case nil: QuickToggleLook(symbol: "wifi.slash", active: false, enabled: false, help: String(localized: "No Wi-Fi Found"))
        }
    }

    public static func microphone(muted: Bool?, settable: Bool) -> QuickToggleLook {
        guard let muted else {
            return QuickToggleLook(symbol: "mic.slash", active: false, enabled: false, help: String(localized: "No Microphone"))
        }
        let state = muted ? String(localized: "Microphone Muted") : String(localized: "Microphone On")
        return QuickToggleLook(
            symbol: muted ? "mic.slash.fill" : "mic.fill",
            active: !muted,
            enabled: settable,
            help: settable ? state : state + String(localized: " (not switchable)")
        )
    }

    public static func bluetooth(powerOn: Bool?) -> QuickToggleLook {
        let state = switch powerOn {
        case true?: String(localized: "Bluetooth On")
        case false?: String(localized: "Bluetooth Off")
        case nil: "Bluetooth"
        }
        return QuickToggleLook(symbol: nil, active: powerOn == true, enabled: true,
                               help: state + String(localized: " – Open Settings"))
    }

    public static let settings = QuickToggleLook(
        symbol: "gearshape.fill", active: false, enabled: true, help: String(localized: "Settings (SUPER+,)")
    )

    public static let columns = 5

    public static func darkMode(on: Bool?) -> QuickToggleLook {
        switch on {
        case true?: QuickToggleLook(symbol: "circle.lefthalf.filled", active: true, enabled: true, help: String(localized: "Dark Mode On"))
        case false?: QuickToggleLook(symbol: "circle.lefthalf.filled", active: false, enabled: true, help: String(localized: "Dark Mode Off"))
        case nil: QuickToggleLook(symbol: "circle.lefthalf.filled", active: false, enabled: false,
                                  help: String(localized: "Dark Mode Unavailable"))
        }
    }

    public static func nightShift(enabled: Bool?) -> QuickToggleLook {
        switch enabled {
        case true?: QuickToggleLook(symbol: "sunset.fill", active: true, enabled: true, help: String(localized: "Night Shift On"))
        case false?: QuickToggleLook(symbol: "sunset.fill", active: false, enabled: true, help: String(localized: "Night Shift Off"))
        case nil: QuickToggleLook(symbol: "sunset.fill", active: false, enabled: false, help: String(localized: "Night Shift Not Available"))
        }
    }

    public static let screenshot = QuickToggleLook(
        symbol: "camera.viewfinder", active: false, enabled: true, help: String(localized: "Screenshot or Recording (⌘⇧5)")
    )

    public static func showDesktop(available: Bool) -> QuickToggleLook {
        QuickToggleLook(
            symbol: "desktopcomputer", active: false, enabled: available,
            help: available ? String(localized: "Show Desktop") : String(localized: "Show Desktop – shortcut turned off in Mission Control")
        )
    }

    public static let colorPicker = QuickToggleLook(
        symbol: "eyedropper", active: false, enabled: true, help: String(localized: "Color Picker – hex value to the clipboard")
    )

    public static let lockScreen = QuickToggleLook(
        symbol: "lock.fill", active: false, enabled: true, help: String(localized: "Lock Screen (⌃⌘Q)")
    )

    public static func cornerRadius(active: Bool, pressed: Bool, height: Double) -> Double {
        if pressed { return 8 }
        return active ? 12 : height / 2
    }
}
