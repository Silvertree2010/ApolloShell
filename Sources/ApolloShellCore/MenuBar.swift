import Foundation

// The menu bar (0.2): one extra bar across the top of the screen, next to
// the sidebar on the left. It has three zones - start, centre, end, from left
// to right - and every zone is an ordinary `BarLayout`, so all modules work
// in all of them.
//
// The sidebar keeps its own section (`ShellSettings.bar`): 0.1.x reads that
// one, and a step back must not lose it. Everything new lives in
// `ShellSettings.apolloMenuBar`, which 0.1.x simply does not know.

// MARK: - Style, zone

/// How the menu bar sits at the top of the screen.
public enum BarStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// One strip across the whole width (Serpantinum: "fill").
    case fill
    /// No strip: every group is an island with a gap to the screen edge
    /// (Serpantinum: "pills").
    case islands

    public var id: Self { self }

    public var title: String {
        switch self {
        case .fill: String(localized: "Strip")
        case .islands: String(localized: "Islands")
        }
    }
}

/// How the status icons module draws Wi-Fi, Bluetooth and battery in the
/// menu bar. Stored as the raw value: never rename a case.
public enum BarStatusStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Glyphs side by side, as in the sidebar.
    case icons
    /// Each one its own coloured capsule with a short text ("Wi-Fi", "On",
    /// "76%"), coloured by the `--apollo-status-*` theme tokens.
    case pills

    public var id: Self { self }
}

/// The three zones of a bar, in reading order.
public enum BarZone: String, Codable, CaseIterable, Sendable, Identifiable {
    case start, center, end

    public var id: Self { self }
}

// MARK: - The bar

/// The menu bar. Always valid: the thickness stays in range, so a
/// hand-edited 10000 can not cover the screen.
public struct ApolloMenuBar: Codable, Equatable, Sendable {
    public static let thicknessRange: ClosedRange<Double> = 24...64
    public static let standardThickness: Double = 34

    public var enabled: Bool
    /// Which screens it stands on.
    public var screens: ScreenChoice
    public var style: BarStyle
    /// In the strip style every group gets its own lighter capsule
    /// (Serpantinum: "distinctPills"). Islands always have one.
    public var distinctGroups: Bool
    /// Height of the bar in points.
    public var thickness: Double {
        didSet {
            let clamped = Self.clamped(thickness)
            if clamped != thickness { thickness = clamped }
        }
    }
    /// Lie over Apple's menu bar instead of below it.
    public var coversMenuBar: Bool
    /// Glyphs or coloured pills for the status icons module. A bar setting
    /// rather than a module option: pills are a look of the whole bar, and
    /// the sidebar has no room for them.
    public var statusStyle: BarStatusStyle
    public var start: BarLayout
    public var center: BarLayout
    public var end: BarLayout

    public init(enabled: Bool = false, screens: ScreenChoice = .all, style: BarStyle = .fill,
                distinctGroups: Bool = false, thickness: Double = ApolloMenuBar.standardThickness,
                coversMenuBar: Bool = true, statusStyle: BarStatusStyle = .icons,
                start: BarLayout = BarLayout(), center: BarLayout = BarLayout(), end: BarLayout = BarLayout()) {
        self.enabled = enabled
        self.screens = screens
        self.style = style
        self.distinctGroups = distinctGroups
        self.thickness = Self.clamped(thickness)
        self.coversMenuBar = coversMenuBar
        self.statusStyle = statusStyle
        self.start = start
        self.center = center
        self.end = end
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, screens, style, distinctGroups, thickness, coversMenuBar, statusStyle, start, center, end
    }

    /// The bar without a settings section: the Serpantinum template,
    /// switched off, so switching it on shows something.
    public static let standard = MenuBarPreset.serpantinum.bar(enabled: false)

    /// Every key on its own: one broken value costs only that value. A key
    /// missing in the file keeps the standard bar's value, zones included:
    /// `{"enabled": true}` shows the Serpantinum bar, not an empty one.
    public init(from decoder: any Decoder) throws {
        self = .standard
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.enabled, into: &enabled)
        c.lenient(.screens, into: &screens)
        c.lenient(.style, into: &style)
        c.lenient(.distinctGroups, into: &distinctGroups)
        // Not `into:`, it would skip `didSet` and with it the clamping.
        if let raw: Double = c.lenient(.thickness) { thickness = Self.clamped(raw) }
        c.lenient(.coversMenuBar, into: &coversMenuBar)
        c.lenient(.statusStyle, into: &statusStyle)
        c.lenient(.start, into: &start)
        c.lenient(.center, into: &center)
        c.lenient(.end, into: &end)
    }

    public subscript(zone: BarZone) -> BarLayout {
        get {
            switch zone {
            case .start: start
            case .center: center
            case .end: end
            }
        }
        set {
            switch zone {
            case .start: start = newValue
            case .center: center = newValue
            case .end: end = newValue
            }
        }
    }

    /// No module in any zone.
    public var isEmpty: Bool { BarZone.allCases.allSatisfy { self[$0].entries.isEmpty } }

    /// Switched on and with something to show.
    public var isActive: Bool { enabled && !isEmpty }

    /// Dock and status icons may stand only once in a whole bar, not once
    /// per zone - the same reasons as in `BarModuleKind.isUnique`.
    public func canAdd(_ kind: BarModuleKind) -> Bool {
        guard kind.isUnique else { return true }
        return !BarZone.allCases.contains { self[$0].contains(kind) }
    }

    public static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return standardThickness }
        return min(max(value, thicknessRange.lowerBound), thicknessRange.upperBound)
    }

    /// The groups of a zone: runs of entries where every entry after the
    /// first one `joinsPrevious`. A group is one capsule in the bar.
    public static func groups(of layout: BarLayout) -> [[BarEntry]] {
        var groups: [[BarEntry]] = []
        for entry in layout.entries {
            if entry.joinsPrevious, !groups.isEmpty {
                groups[groups.count - 1].append(entry)
            } else {
                groups.append([entry])
            }
        }
        return groups
    }
}

// MARK: - Templates

/// Ready-made menu bars. "Serpantinum" follows the look this was built after
/// (its idea, not its code): settings, spaces and media on the left, clock
/// and weather in the middle, the status pills on the right.
public enum MenuBarPreset: String, CaseIterable, Identifiable, Sendable {
    case serpantinum, minimal, clockOnly

    public var id: Self { self }

    public var title: String {
        switch self {
        case .serpantinum: "Serpantinum"
        case .minimal: "Minimal"
        case .clockOnly: "Clock Only"
        }
    }

    public var summary: String {
        switch self {
        case .serpantinum: "Spaces and media on the left, clock and weather in the middle, status on the right."
        case .minimal: "Spaces on the left, the clock on the right."
        case .clockOnly: "Just the clock in the middle."
        }
    }

    /// The template as a bar, its other settings at their defaults.
    public func bar(enabled: Bool = true) -> ApolloMenuBar {
        switch self {
        case .serpantinum:
            ApolloMenuBar(enabled: enabled,
                          start: BarLayout([BarEntry(.dashboardButton), BarEntry(.workspaces), BarEntry(.mediaButton)]),
                          center: BarLayout([BarEntry(module: .clock(.init(showIcon: false, showDate: true))),
                                             BarEntry(.weather).joined()]),
                          // The battery as its own module with its number, so not
                          // a second time as a glyph in the status capsule.
                          end: BarLayout([BarEntry(module: .statusIcons(.init(showBattery: false))),
                                          BarEntry(.battery).joined(), BarEntry(.power)]))
        case .minimal:
            ApolloMenuBar(enabled: enabled,
                          start: BarLayout([BarEntry(.workspaces)]),
                          end: BarLayout([BarEntry(module: .clock(.init(showIcon: false)))]))
        case .clockOnly:
            ApolloMenuBar(enabled: enabled, center: BarLayout([BarEntry(module: .clock(.init(showIcon: false)))]))
        }
    }
}
