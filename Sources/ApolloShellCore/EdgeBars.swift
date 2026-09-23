import Foundation

// Bars along the other screen edges (0.2): top, bottom and right, next to
// the sidebar on the left. Each one has three zones - start, centre, end -
// and every zone is an ordinary `BarLayout`, so all modules work in all of
// them. In a vertical bar "start" is the top, in a horizontal one the left.
//
// The sidebar keeps its own section (`ShellSettings.bar`): 0.1.x reads that
// one, and a step back must not lose it. Everything new lives in
// `ShellSettings.edgeBars`, which 0.1.x simply does not know.

// MARK: - Edge, style, zone

/// The screen edge a bar runs along. The raw value is stored in the file,
/// so never rename it.
public enum BarEdge: String, Codable, CaseIterable, Sendable, Identifiable {
    case top, bottom, right

    public var id: Self { self }

    /// Modules run from left to right (top, bottom) instead of from top to
    /// bottom (right).
    public var isHorizontal: Bool { self != .right }

    public var title: String {
        switch self {
        case .top: String(localized: "Top")
        case .bottom: String(localized: "Bottom")
        case .right: String(localized: "Right")
        }
    }
}

/// How a bar sits on its edge.
public enum BarStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// One strip along the whole edge (Serpantinum: "fill").
    case fill
    /// No strip: every group is an island with a gap to the edge
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

/// The three zones of a bar, in reading order.
public enum BarZone: String, Codable, CaseIterable, Sendable, Identifiable {
    case start, center, end

    public var id: Self { self }
}

// MARK: - One bar

/// A bar along one edge. Always valid: the thickness stays in range, so a
/// hand-edited 10000 can not cover the screen.
public struct EdgeBar: Codable, Equatable, Sendable {
    public static let thicknessRange: ClosedRange<Double> = 24...64
    public static let standardThickness: Double = 34

    public var enabled: Bool
    /// Which screens it stands on.
    public var screens: ScreenChoice
    public var style: BarStyle
    /// In the strip style every group gets its own lighter capsule
    /// (Serpantinum: "distinctPills"). Islands always have one.
    public var distinctGroups: Bool
    /// Height of a horizontal bar, width of a vertical one, in points.
    public var thickness: Double {
        didSet {
            let clamped = Self.clamped(thickness)
            if clamped != thickness { thickness = clamped }
        }
    }
    /// Only for the top edge: lie over Apple's menu bar instead of below it.
    public var coversMenuBar: Bool
    public var start: BarLayout
    public var center: BarLayout
    public var end: BarLayout

    public init(enabled: Bool = false, screens: ScreenChoice = .all, style: BarStyle = .fill,
                distinctGroups: Bool = false, thickness: Double = EdgeBar.standardThickness,
                coversMenuBar: Bool = true,
                start: BarLayout = BarLayout(), center: BarLayout = BarLayout(), end: BarLayout = BarLayout()) {
        self.enabled = enabled
        self.screens = screens
        self.style = style
        self.distinctGroups = distinctGroups
        self.thickness = Self.clamped(thickness)
        self.coversMenuBar = coversMenuBar
        self.start = start
        self.center = center
        self.end = end
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, screens, style, distinctGroups, thickness, coversMenuBar, start, center, end
    }

    /// Every key on its own: one broken value costs only that value.
    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.enabled, into: &enabled)
        c.lenient(.screens, into: &screens)
        c.lenient(.style, into: &style)
        c.lenient(.distinctGroups, into: &distinctGroups)
        // Not `into:`, it would skip `didSet` and with it the clamping.
        if let raw: Double = c.lenient(.thickness) { thickness = Self.clamped(raw) }
        c.lenient(.coversMenuBar, into: &coversMenuBar)
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

/// Ready-made bars. "Serpantinum" follows the look this was built after
/// (its idea, not its code): settings, spaces and media on the left, clock
/// and weather in the middle, the status pills on the right.
public enum EdgeBarPreset: String, CaseIterable, Identifiable, Sendable {
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

    /// The zones of the template, for a bar of any edge.
    public func bar(edge: BarEdge, enabled: Bool = true) -> EdgeBar {
        switch self {
        case .serpantinum:
            EdgeBar(enabled: enabled,
                    start: BarLayout([BarEntry(.dashboardButton), BarEntry(.workspaces), BarEntry(.mediaButton)]),
                    center: BarLayout([BarEntry(module: .clock(.init(showIcon: false, showDate: true))),
                                       BarEntry(.weather).joined()]),
                    // The battery as its own module with its number, so not
                    // a second time as a glyph in the status capsule.
                    end: BarLayout([BarEntry(module: .statusIcons(.init(showBattery: false))),
                                    BarEntry(.battery).joined(), BarEntry(.power)]))
        case .minimal:
            EdgeBar(enabled: enabled,
                    start: BarLayout([BarEntry(.workspaces)]),
                    end: BarLayout([BarEntry(module: .clock(.init(showIcon: false)))]))
        case .clockOnly:
            EdgeBar(enabled: enabled, center: BarLayout([BarEntry(module: .clock(.init(showIcon: false)))]))
        }
    }
}

// MARK: - All bars

/// The bars of the three other edges. Missing ones are off; the top bar
/// starts with the Serpantinum template so switching it on shows something.
public struct EdgeBars: Codable, Equatable, Sendable {
    public var top: EdgeBar
    public var bottom: EdgeBar
    public var right: EdgeBar

    public init(top: EdgeBar = EdgeBarPreset.serpantinum.bar(edge: .top, enabled: false),
                bottom: EdgeBar = EdgeBarPreset.minimal.bar(edge: .bottom, enabled: false),
                right: EdgeBar = EdgeBarPreset.minimal.bar(edge: .right, enabled: false)) {
        self.top = top
        self.bottom = bottom
        self.right = right
    }

    private enum CodingKeys: String, CodingKey { case top, bottom, right }

    /// A zone missing in the file keeps the template's zone: `{"top":
    /// {"enabled": true}}` shows the Serpantinum bar, not an empty one.
    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        for (key, edge) in [(CodingKeys.top, BarEdge.top), (.bottom, .bottom), (.right, .right)] {
            guard var bar: EdgeBar = c.lenient(key) else { continue }
            if let zones = try? c.nestedContainer(keyedBy: ZoneKey.self, forKey: key) {
                for zone in BarZone.allCases where !zones.contains(ZoneKey(zone)) {
                    bar[zone] = self[edge][zone]
                }
            }
            self[edge] = bar
        }
    }

    private struct ZoneKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ zone: BarZone) { stringValue = zone.rawValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public subscript(edge: BarEdge) -> EdgeBar {
        get {
            switch edge {
            case .top: top
            case .bottom: bottom
            case .right: right
            }
        }
        set {
            switch edge {
            case .top: top = newValue
            case .bottom: bottom = newValue
            case .right: right = newValue
            }
        }
    }

    /// The bars that are switched on and have something to show.
    public var active: [BarEdge] {
        BarEdge.allCases.filter { self[$0].enabled && !self[$0].isEmpty }
    }
}
