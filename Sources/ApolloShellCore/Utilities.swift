import Foundation

/// The texts of the "Keep Awake" card in the utilities panel (Caelestia: IdleInhibit).
public enum KeepAwakeText {
    public static let title = String(localized: "Keep Awake")
    public static let inactive = String(localized: "Mac sleeps normally")

    /// "Active since 14:30". When it has been running since yesterday or
    /// longer, the day belongs with it - otherwise one reads "since 23:10" in
    /// the morning as "this evening".
    ///
    /// A fixed 24-hour spelling instead of a DateFormatter with a locale, so
    /// the result is testably the same. `lidClosed`: it holds with the lid
    /// closed too (`LidAwake`) - one should see that, because it leaves the Mac awake.
    public static func subtitle(since: Date?, now: Date, lidClosed: Bool = false, calendar: Calendar = .current) -> String {
        subtitle(since: since, now: now, lid: lidClosed ? .on : .off, calendar: calendar)
    }

    /// With the state of the lid part: also say when it is missing although it
    /// is set (the administrator refused) - otherwise one would close the Mac
    /// believing it stays awake.
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

/// What a quick toggle shows: the symbol, whether it lights up (accent
/// color), whether it is clickable, and the text for the tooltip and VoiceOver.
public struct QuickToggleLook: Equatable, Sendable {
    /// An SF Symbol. `nil` means the Bluetooth rune: there is no SF Symbol for
    /// it, and the user interface draws it itself.
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

/// The quick toggles of the utilities panel (Caelestia: Toggles) and their
/// shape. "Lights up" always means "is on", as in Caelestia - so with the
/// microphone "not muted" (Caelestia: `checked: !Audio.sourceMuted`), so that
/// the whole row reads the same way.
public enum QuickToggles {
    /// `nil`: no Wi-Fi interface found, and then there is nothing to switch.
    public static func wifi(powerOn: Bool?) -> QuickToggleLook {
        switch powerOn {
        case true?: QuickToggleLook(symbol: "wifi", active: true, enabled: true, help: String(localized: "Wi-Fi On"))
        case false?: QuickToggleLook(symbol: "wifi.slash", active: false, enabled: true, help: String(localized: "Wi-Fi Off"))
        case nil: QuickToggleLook(symbol: "wifi.slash", active: false, enabled: false, help: String(localized: "No Wi-Fi Found"))
        }
    }

    /// `muted == nil`: no input device. `settable == false`: the device knows
    /// no (writable) mute - showing yes, clicking no.
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

    /// Bluetooth only shows the state; switching does not work without private
    /// interfaces, so the click opens the Bluetooth settings.
    public static func bluetooth(powerOn: Bool?) -> QuickToggleLook {
        let state = switch powerOn {
        case true?: String(localized: "Bluetooth On")
        case false?: String(localized: "Bluetooth Off")
        case nil: "Bluetooth"
        }
        return QuickToggleLook(symbol: nil, active: powerOn == true, enabled: true,
                               help: state + String(localized: " – Open Settings"))
    }

    /// No switch, only a button: never lights up. Opens our own settings
    /// window (Nexus) as in Caelestia, not System Settings - those are one
    /// line away from Nexus.
    public static let settings = QuickToggleLook(
        symbol: "gearshape.fill", active: false, enabled: true, help: String(localized: "Settings (SUPER+,)")
    )

    /// Buttons per row. The default is two rows of five: the switches with a
    /// state at the top, the actions at the bottom - that way one reads the
    /// rows like Apple's Control Centre. How many rows it becomes is decided
    /// by the arrangement in Nexus (`UtilitiesLayout.toggleRows`).
    public static let columns = 5

    /// Lights up in dark mode. `nil`: the state cannot be read (neither
    /// SkyLight nor the preference) - then it is not clickable.
    public static func darkMode(on: Bool?) -> QuickToggleLook {
        switch on {
        case true?: QuickToggleLook(symbol: "circle.lefthalf.filled", active: true, enabled: true, help: String(localized: "Dark Mode On"))
        case false?: QuickToggleLook(symbol: "circle.lefthalf.filled", active: false, enabled: true, help: String(localized: "Dark Mode Off"))
        case nil: QuickToggleLook(symbol: "circle.lefthalf.filled", active: false, enabled: false,
                                  help: String(localized: "Dark Mode Unavailable"))
        }
    }

    /// `nil`: this Mac or screen cannot do Night Shift, or CoreBrightness does
    /// not answer. The button then stays visible but off - that way the grid
    /// keeps its fixed shape.
    public static func nightShift(enabled: Bool?) -> QuickToggleLook {
        switch enabled {
        case true?: QuickToggleLook(symbol: "sunset.fill", active: true, enabled: true, help: String(localized: "Night Shift On"))
        case false?: QuickToggleLook(symbol: "sunset.fill", active: false, enabled: true, help: String(localized: "Night Shift Off"))
        case nil: QuickToggleLook(symbol: "sunset.fill", active: false, enabled: false, help: String(localized: "Night Shift Not Available"))
        }
    }

    /// Actions never light up, they have no state.
    public static let screenshot = QuickToggleLook(
        symbol: "camera.viewfinder", active: false, enabled: true, help: String(localized: "Screenshot or Recording (⌘⇧5)")
    )

    /// `available == false`: the shortcut is switched off in Mission Control -
    /// without it there is no way, so it is not clickable.
    /// The symbol: a screen with an empty desktop. "menubar.dock.rectangle"
    /// read like a credit card in the image sample of 14.09.
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

    /// The corner radius as in Caelestia's IconButton with `shapeMorph`: off
    /// fully round (half the height), on a rounded rectangle with 12, pressed 8.
    public static func cornerRadius(active: Bool, pressed: Bool, height: Double) -> Double {
        if pressed { return 8 }
        return active ? 12 : height / 2
    }
}
