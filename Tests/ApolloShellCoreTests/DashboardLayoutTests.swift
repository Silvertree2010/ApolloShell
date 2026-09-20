import Foundation
import Testing
@testable import ApolloShellCore

@Suite("The dashboard as a kit: tabs, cards, templates, measurements")
struct DashboardLayoutTests {
    private func tabs(_ json: String) -> DashboardTabs? {
        try? JSONDecoder().decode(DashboardTabs.self, from: Data(json.utf8))
    }

    private func cards(_ json: String) -> DashboardCards? {
        try? JSONDecoder().decode(DashboardCards.self, from: Data(json.utf8))
    }

    /// "top|bottom|side" with the kinds per place, for comparing.
    private func text(_ cards: DashboardCards?) -> String {
        guard let cards else { return "<nicht lesbar>" }
        return DashboardZone.allCases.map { cards[$0].map(\.kind.rawValue).joined(separator: ",") }.joined(separator: "|")
    }

    private func grid(_ text: String) -> DashboardCards {
        let zones = text.split(separator: "|", omittingEmptySubsequences: false).map { part in
            part.split(separator: ",").compactMap { DashboardCardKind(rawValue: String($0)) }
        }
        return DashboardCards(top: zones[0], bottom: zones[1], side: zones[2])
    }

    // MARK: Tabs

    @Test("Reading tabs: the unknown and the duplicate go, the missing become visible at the end", arguments: [
        (#"[{"id":"weather","visible":false},{"id":"media"},{"id":"x"},5,{"id":"weather"}]"#,
         ["weather", "media", "dashboard", "performance"], ["weather"]),
        (#"[]"#, ["dashboard", "media", "performance", "weather"], []),
        (#"[{"id":"performance","visible":"nein"}]"#, ["performance", "dashboard", "media", "weather"], []),
        (#"[{"id":"media","visible":false},{"id":"dashboard","visible":false},{"id":"performance","visible":false},{"id":"weather","visible":false}]"#,
         ["media", "dashboard", "performance", "weather"], ["dashboard", "performance", "weather"]),
    ])
    func tabsDecode(json: String, order: [String], hidden: [String]) {
        let tabs = tabs(json)
        #expect(tabs?.order.map(\.rawValue) == order)
        #expect(tabs.map { $0.hidden.map(\.rawValue).sorted() } == hidden.sorted())
    }

    @Test("no tab array: the default", arguments: [#"{"tabs":5}"#, #"{"tabs":{"a":1}}"#, "{}"])
    func tabsFallback(json: String) throws {
        let layout = try JSONDecoder().decode(DashboardLayout.self, from: Data(json.utf8))
        #expect(layout.tabs == DashboardTabs())
    }

    @Test("a hidden tab: the first visible one steps in", arguments: [
        (DashboardTab.media, DashboardTab.dashboard), (DashboardTab.weather, DashboardTab.weather),
        (DashboardTab.performance, DashboardTab.dashboard),
    ])
    func tabsResolved(wanted: DashboardTab, shown: DashboardTab) {
        let tabs = DashboardTabs(hidden: [.media, .performance])
        #expect(tabs.resolved(wanted) == shown)
        // With another order "the first one" is a different one.
        let reordered = DashboardTabs(order: [.weather, .dashboard, .media, .performance], hidden: [.media])
        #expect(reordered.resolved(.media) == .weather)
    }

    @Test("the last visible tab stays")
    func tabsKeepOne() {
        var tabs = DashboardTabs()
        tabs.setVisible(.media, false)
        tabs.setVisible(.performance, false)
        tabs.setVisible(.weather, false)
        #expect(!tabs.canHide(.dashboard))
        tabs.setVisible(.dashboard, false)
        #expect(tabs.visible == [.dashboard])
        tabs.setVisible(.weather, true)
        #expect(tabs.visible == [.dashboard, .weather])
        #expect(tabs.canHide(.dashboard))
    }

    @Test("dragging and pushing tabs", arguments: [
        ([3], 0, ["weather", "dashboard", "media", "performance"]),
        ([0], 4, ["media", "performance", "weather", "dashboard"]),
        ([7], 0, ["dashboard", "media", "performance", "weather"]),
    ])
    func tabsMove(source: [Int], destination: Int, expected: [String]) {
        var tabs = DashboardTabs()
        tabs.move(fromOffsets: IndexSet(source), toOffset: destination)
        #expect(tabs.order.map(\.rawValue) == expected)
    }

    @Test("a tab one place, nothing at the edge", arguments: [
        (DashboardTab.media, -1, ["media", "dashboard", "performance", "weather"]),
        (DashboardTab.weather, 1, ["dashboard", "media", "performance", "weather"]),
    ])
    func tabsStep(tab: DashboardTab, step: Int, expected: [String]) {
        var tabs = DashboardTabs()
        tabs.move(tab, by: step)
        #expect(tabs.order.map(\.rawValue) == expected)
    }

    // MARK: Reading cards

    @Test("Reading cards: a missing place = the default, an empty list = empty", arguments: [
        ("{}", "weather,user|clock,calendar,resources|media"),
        (#"{"top":[]}"#, "|clock,calendar,resources|media"),
        (#"{"top":5,"side":[]}"#, "weather,user|clock,calendar,resources|"),
        (#"{"top":[],"bottom":[],"side":[]}"#, "||"),
    ])
    func cardsZones(json: String, expected: String) {
        #expect(text(cards(json)) == expected)
    }

    @Test("Reading cards: every rule only throws away what it breaks", arguments: [
        // Unknown and no object
        (#"{"top":[{"kind":"hologram"},7,{"kind":"weather"}],"bottom":[],"side":[]}"#, "weather||"),
        // Duplicate: the first one counts (top before bottom before column)
        (#"{"top":[{"kind":"media"}],"bottom":[{"kind":"media"},{"kind":"clock"}]}"#, "media|clock|"),
        // The calendar only at the bottom
        (#"{"top":[{"kind":"calendar"}],"bottom":[],"side":[{"kind":"calendar"}]}"#, "||"),
        // The column: one card
        (#"{"top":[],"bottom":[],"side":[{"kind":"user"},{"kind":"clock"}]}"#, "||user"),
        // The row too wide: 275 + 230 + 12 fits, plus 300 + 12 no longer
        (#"{"top":[{"kind":"weather"},{"kind":"user"},{"kind":"media"},{"kind":"clock"}],"bottom":[],"side":[]}"#, "weather,user||"),
    ])
    func cardsRules(json: String, expected: String) {
        #expect(text(cards(json)) == expected)
    }

    @Test("broken options: the defaults, readable fields stay", arguments: [
        (#"{"top":[{"kind":"weather","options":{"showRange":false,"future":1}}]}"#, DashboardCard.weather(.init(showRange: false))),
        (#"{"top":[{"kind":"user","options":[]}]}"#, DashboardCard.user(.init())),
        (#"{"top":[{"kind":"clock","options":{"style":"analog","showDate":true}}]}"#, DashboardCard.clock(.init(showDate: true))),
        (#"{"top":[{"kind":"clock","options":{"style":"inline"}}]}"#, DashboardCard.clock(.init(style: .inline))),
        (#"{"top":[{"kind":"resources","options":{"showCPU":false,"showMemory":false,"showStorage":false}}]}"#, DashboardCard.resources(.init())),
        (#"{"top":[{"kind":"resources","options":{"showMemory":false,"showStorage":"nein"}}]}"#, DashboardCard.resources(.init(showMemory: false))),
        (#"{"top":[{"kind":"media","options":{"showSource":false}}]}"#, DashboardCard.media(.init(showSource: false))),
    ])
    func lenientOptions(json: String, expected: DashboardCard) {
        #expect(cards(json)?.top.first == expected)
    }

    @Test("Reading calendar options", arguments: [
        (#"{"bottom":[{"kind":"calendar","options":{"firstWeekday":"sunday","showWeekNumbers":true}}]}"#,
         DashboardCalendarOptions(firstWeekday: .sunday, showWeekNumbers: true)),
        (#"{"bottom":[{"kind":"calendar","options":{"firstWeekday":"friday"}}]}"#, DashboardCalendarOptions()),
    ])
    func calendarOptions(json: String, expected: DashboardCalendarOptions) {
        #expect(cards(json)?.bottom.first?.calendar == expected)
    }

    @Test("every card at every allowed place survives writing and reading", arguments: DashboardCardKind.allCases)
    func roundTripEveryZone(kind: DashboardCardKind) throws {
        for zone in kind.zones {
            let cards = DashboardCards(top: zone == .top ? [kind] : [], bottom: zone == .bottom ? [kind] : [],
                                       side: zone == .side ? [kind] : [])
            #expect(cards[zone].map(\.kind) == [kind])
            let data = try JSONEncoder().encode(cards)
            #expect(try JSONDecoder().decode(DashboardCards.self, from: data) == cards)
        }
    }

    @Test("kind, name, description, symbol and places are complete", arguments: DashboardCardKind.allCases)
    func kindMetadata(kind: DashboardCardKind) {
        #expect(DashboardCard(kind).kind == kind)
        #expect(!kind.title.isEmpty && !kind.summary.isEmpty && !kind.symbol.isEmpty)
        #expect(kind.zones.first == kind.home)
        #expect(Set(kind.zones).count == kind.zones.count)
    }

    @Test("only ask for weather and playback when a card or a tab can be seen", arguments: [
        (DashboardPreset.caelestia.layout, true, true),
        (DashboardPreset.calendarWeather.layout, true, false),
        // The card is there, but the dashboard tab is hidden: does not count.
        (DashboardLayout(tabs: DashboardTabs(hidden: [.dashboard, .weather])), false, true),
        (DashboardLayout(tabs: DashboardTabs(hidden: [.media, .weather]), cards: DashboardCards(top: [], bottom: [.calendar], side: [])),
         false, false),
    ])
    func usesData(layout: DashboardLayout, weather: Bool, media: Bool) {
        #expect(layout.usesWeather == weather)
        #expect(layout.usesMedia == media)
    }

    // MARK: Settings

    @Test("without a dashboard section: the dashboard from before", arguments: [
        "{}", #"{"dashboard":5}"#, #"{"dashboard":{}}"#, #"{"bar":{},"dashboard":null}"#,
    ])
    func settingsMigration(json: String) {
        let settings = ShellSettings.load(from: Data(json.utf8))
        #expect(settings.dashboard == DashboardLayout())
        #expect(settings.dashboard == DashboardPreset.caelestia.layout)
        #expect(settings.dashboard.cards == .caelestia)
    }

    @Test("the dashboard section: only it differs, the bar stays the default")
    func settingsPartial() {
        let json = #"{"dashboard":{"tabs":[{"id":"media","visible":false}],"cards":{"side":[]}}}"#
        let settings = ShellSettings.load(from: Data(json.utf8))
        #expect(settings.bar == ShellSettings().bar)
        #expect(settings.dashboard.tabs.visible == [.dashboard, .performance, .weather])
        #expect(text(settings.dashboard.cards) == "weather,user|clock,calendar,resources|")
    }

    @Test("settings.json with a dashboard survives writing and reading", arguments: DashboardPreset.allCases)
    func settingsRoundTrip(preset: DashboardPreset) {
        let settings = ShellSettings(dashboard: preset.layout)
        #expect(ShellSettings.load(from: settings.encoded()) == settings)
        let written = String(decoding: settings.encoded(), as: UTF8.self)
        for key in ["\"dashboard\"", "\"tabs\"", "\"visible\"", "\"cards\"", "\"top\"", "\"bottom\"", "\"side\""] {
            #expect(written.contains(key))
        }
    }

    // MARK: Templates

    @Test("templates are data", arguments: [
        (DashboardPreset.caelestia, "weather,user|clock,calendar,resources|media", ["dashboard", "media", "performance", "weather"]),
        (DashboardPreset.compact, "weather,media|clock,calendar,resources|", ["dashboard", "media", "performance", "weather"]),
        (DashboardPreset.calendarWeather, "|clock,calendar|weather", ["dashboard", "weather"]),
    ])
    func presetContent(preset: DashboardPreset, cards: String, visibleTabs: [String]) {
        #expect(text(preset.layout.cards) == cards)
        #expect(preset.layout.tabs.visible.map(\.rawValue) == visibleTabs)
    }

    @Test("templates are valid and already in normal form", arguments: DashboardPreset.allCases)
    func presetValid(preset: DashboardPreset) throws {
        let layout = preset.layout
        #expect(!preset.title.isEmpty && !preset.summary.isEmpty && !layout.cards.isEmpty)
        let c = layout.cards
        #expect(DashboardCards(top: c.top, bottom: c.bottom, side: c.side) == c)
        #expect(try JSONDecoder().decode(DashboardLayout.self, from: JSONEncoder().encode(layout)) == layout)
    }

    // MARK: Changing cards

    @Test("adding: to the Caelestia place, otherwise to the first one with room", arguments: [
        ("|clock,calendar|", DashboardCardKind.resources, "|clock,calendar,resources|"),
        ("user|clock,calendar,resources|weather", DashboardCardKind.media, "user,media|clock,calendar,resources|weather"),
        ("weather,user|clock,calendar,resources|", DashboardCardKind.media, "weather,user|clock,calendar,resources|media"),
        ("weather,user|calendar,resources|media", DashboardCardKind.clock, "weather,user|calendar,resources,clock|media"),
        ("||", DashboardCardKind.calendar, "|calendar|"),
    ])
    func add(start: String, kind: DashboardCardKind, expected: String) {
        var cards = grid(start)
        #expect(cards.add(kind) != nil)
        #expect(text(cards) == expected)
    }

    @Test("hinzufuegen geht nicht: schon da, oder nirgends Raum", arguments: [
        ("weather,user|clock,calendar,resources|media", DashboardCardKind.clock),
        // The bottom 200 + 200 + 110 + 24 = 534; with the calendar (300) too wide.
        ("|weather,user,clock|media", DashboardCardKind.calendar),
    ])
    func addRefused(start: String, kind: DashboardCardKind) {
        var cards = grid(start)
        #expect(!cards.canAdd(kind))
        #expect(cards.add(kind) == nil)
        #expect(cards == grid(start))
    }

    @Test("removing, and adding it again afterwards")
    func remove() {
        var cards = DashboardCards.caelestia
        cards.remove(.calendar)
        #expect(text(cards) == "weather,user|clock,resources|media")
        #expect(cards.canAdd(.calendar))
        cards.remove(.calendar)
        #expect(text(cards) == "weather,user|clock,resources|media")
    }

    @Test("dragging within one place", arguments: [
        (DashboardZone.bottom, [2], 0, "weather,user|resources,clock,calendar|media"),
        (DashboardZone.top, [0], 2, "user,weather|clock,calendar,resources|media"),
        (DashboardZone.side, [0], 1, "weather,user|clock,calendar,resources|media"),
    ])
    func moveOffsets(zone: DashboardZone, source: [Int], destination: Int, expected: String) {
        var cards = DashboardCards.caelestia
        cards.move(in: zone, fromOffsets: IndexSet(source), toOffset: destination)
        #expect(text(cards) == expected)
    }

    @Test("one place left or right, nothing at the edge", arguments: [
        (DashboardCardKind.clock, 1, "weather,user|calendar,clock,resources|media"),
        (DashboardCardKind.user, -1, "user,weather|clock,calendar,resources|media"),
        (DashboardCardKind.resources, 1, "weather,user|clock,calendar,resources|media"),
        (DashboardCardKind.media, -1, "weather,user|clock,calendar,resources|media"),
    ])
    func moveStep(kind: DashboardCardKind, step: Int, expected: String) {
        var cards = DashboardCards.caelestia
        cards.move(kind, by: step)
        #expect(text(cards) == expected)
    }

    @Test("to another place; an occupied column swaps", arguments: [
        // The weather into the column: the media take the place of the weather.
        ("weather,user|clock,calendar,resources|media", DashboardCardKind.weather, DashboardZone.side, true,
         "media,user|clock,calendar,resources|weather"),
        // The clock to the top: 275 + 230 + 110 + 24 = 639 > 627.
        ("weather,user|clock,calendar,resources|media", DashboardCardKind.clock, DashboardZone.top, false,
         "weather,user|clock,calendar,resources|media"),
        ("weather|clock,calendar,resources|media", DashboardCardKind.resources, DashboardZone.top, true,
         "weather,resources|clock,calendar|media"),
        // The calendar may only stand at the bottom.
        ("weather|clock,calendar|", DashboardCardKind.calendar, DashboardZone.top, false, "weather|clock,calendar|"),
        // The media into the bottom row: 110 + 300 + 90 + 200 + 36 = 736, too wide.
        ("weather,user|clock,calendar,resources|media", DashboardCardKind.media, DashboardZone.bottom, false,
         "weather,user|clock,calendar,resources|media"),
        // Without the clock it fits: 300 + 200 + 12 = 512.
        ("weather,user|calendar|media", DashboardCardKind.media, DashboardZone.bottom, true,
         "weather,user|calendar,media|"),
        // A swap after which the column card would be too wide at the old
        // place: the bottom 110 + 300 + 200 + 24 = 634 > 627 - no.
        ("weather,user|clock,calendar,resources|media", DashboardCardKind.resources, DashboardZone.side, false,
         "weather,user|clock,calendar,resources|media"),
        // There already: nothing.
        ("weather,user|clock,calendar,resources|media", DashboardCardKind.user, DashboardZone.top, false,
         "weather,user|clock,calendar,resources|media"),
    ])
    func moveZone(start: String, kind: DashboardCardKind, zone: DashboardZone, ok: Bool, expected: String) {
        var cards = grid(start)
        #expect(cards.canMove(kind, to: zone) == ok)
        #expect(cards.move(kind, to: zone) == ok)
        #expect(text(cards) == expected)
    }

    @Test("swapping", arguments: [
        (DashboardCardKind.clock, DashboardCardKind.resources, true, "weather,user|resources,calendar,clock|media"),
        (DashboardCardKind.weather, DashboardCardKind.user, true, "user,weather|clock,calendar,resources|media"),
        // The weather at the bottom instead of the clock: 200 + 300 + 90 + 24 = 614 fits; the clock at the top next to the user too.
        (DashboardCardKind.weather, DashboardCardKind.clock, true, "clock,user|weather,calendar,resources|media"),
        (DashboardCardKind.calendar, DashboardCardKind.weather, false, "weather,user|clock,calendar,resources|media"),
        (DashboardCardKind.media, DashboardCardKind.clock, true, "weather,user|media,calendar,resources|clock"),
        (DashboardCardKind.media, DashboardCardKind.media, false, "weather,user|clock,calendar,resources|media"),
    ])
    func swap(a: DashboardCardKind, b: DashboardCardKind, ok: Bool, expected: String) {
        var cards = DashboardCards.caelestia
        #expect(cards.canSwap(a, b) == ok)
        #expect(cards.swap(a, b) == ok)
        #expect(text(cards) == expected)
    }

    @Test("changing options: the place and the order stay")
    func update() {
        var cards = DashboardCards.caelestia
        cards.update(.clock(.init(style: .inline, showDate: true)))
        #expect(cards[kind: .clock] == .clock(.init(style: .inline, showDate: true)))
        #expect(text(cards) == text(.caelestia))
        // A card that is not there: nothing.
        cards.remove(.user)
        cards.update(.user(.init(showUptime: false)))
        #expect(!cards.contains(.user))
    }

    // MARK: Measurements

    private func frames(_ cards: DashboardCards) -> [String] {
        DashboardGeometry.placements(for: cards).map {
            "\($0.card.kind.rawValue) \(Int($0.frame.x)) \(Int($0.frame.y)) \(Int($0.frame.width)) \(Int($0.frame.height))"
        }
    }

    @Test("Caelestia: exactly the fixed measurements from before")
    func caelestiaFrames() {
        #expect(DashboardGeometry.rowWidth == 627)
        #expect(frames(.caelestia) == [
            "weather 0 0 275 130", "user 287 0 340 130",
            "clock 0 142 110 250", "calendar 122 142 403 250", "resources 537 142 90 250",
            "media 639 0 200 392",
        ])
    }

    @Test("empty places fill the neighbours", arguments: [
        // Without the column: the rows go across the whole width.
        ("weather,media|clock,calendar,resources|",
         ["weather 0 0 275 130", "media 287 0 552 130", "clock 0 142 110 250", "calendar 122 142 615 250",
          "resources 749 142 90 250"]),
        // Without the top row: the bottom one gets the whole height.
        ("|clock,calendar|weather", ["clock 0 0 110 392", "calendar 122 0 505 392", "weather 639 0 200 392"]),
        // Only fixed cards: stretched in proportion, the rest to the last one.
        ("|clock,resources|media", ["clock 0 0 338 392", "resources 350 0 277 392", "media 639 0 200 392"]),
        // Only the column: it gets everything.
        ("||media", ["media 0 0 839 392"]),
        ("||", []),
    ])
    func stretchFrames(start: String, expected: [String]) {
        #expect(frames(grid(start)) == expected)
    }

    @Test("the widths of a row", arguments: [
        ([DashboardCardWidth.fixed(275), .flexible(minimum: 230)], 627.0, [275.0, 340.0]),
        ([DashboardCardWidth.flexible(minimum: 300), .flexible(minimum: 230)], 627.0, [307.0, 308.0]),
        ([DashboardCardWidth.fixed(110), .fixed(90)], 627.0, [338.0, 277.0]),
        // Too tight (does not come up after `fits`): squeezed instead of over the edge.
        ([DashboardCardWidth.fixed(300), .fixed(300), .flexible(minimum: 100)], 524.0, [214.0, 214.0, 72.0]),
        ([DashboardCardWidth.fixed(200)], 839.0, [839.0]),
        ([] as [DashboardCardWidth], 627.0, [] as [Double]),
    ])
    func rowWidths(widths: [DashboardCardWidth], available: Double, expected: [Double]) {
        let result = DashboardGeometry.widths(available: available, widths: widths, spacing: 12)
        #expect(result == expected)
        if !widths.isEmpty {
            #expect(result.reduce(0, +) + Double(widths.count - 1) * 12 == available)
        }
    }

    @Test("every allowed arrangement out of a template fits into the area", arguments: DashboardPreset.allCases)
    func placementsInside(preset: DashboardPreset) {
        for placement in DashboardGeometry.placements(for: preset.layout.cards) {
            let f = placement.frame
            #expect(f.x >= 0 && f.y >= 0 && f.width > 0 && f.height > 0)
            #expect(f.x + f.width <= DashboardGeometry.width && f.y + f.height <= DashboardGeometry.height)
            #expect(f.x == f.x.rounded() && f.width == f.width.rounded())
        }
    }

    // MARK: Calendar

    private func calendar(_ weekday: DashboardCalendarOptions.FirstWeekday) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_CH")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.minimumDaysInFirstWeek = 4
        return DashboardCalendarOptions(firstWeekday: weekday).applied(to: calendar)
    }

    @Test("calendar weeks and weekdays per first weekday", arguments: [
        (DashboardCalendarOptions.FirstWeekday.monday, [36, 37, 38, 39, 40], "Mo", 31),
        (DashboardCalendarOptions.FirstWeekday.sunday, [35, 36, 37, 38, 39], "So", 30),
    ])
    func weekNumbers(weekday: DashboardCalendarOptions.FirstWeekday, expected: [Int], firstSymbol: String, firstDay: Int) {
        let calendar = calendar(weekday)
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 12))!
        let weeks = CalendarMonth.weeks(for: day, today: day, calendar: calendar)
        #expect(CalendarMonth.weekNumbers(weeks, calendar: calendar) == expected)
        #expect(CalendarMonth.weekdaySymbols(calendar: calendar).first == firstSymbol)
        #expect(weeks.first?.first?.day == firstDay)
    }

    // MARK: Clock time zone (0.2)

    @Test("Clock: read the time zone, an unknown one counts as the system, nil is not written")
    func clockTimeZone() throws {
        let tokyo = try JSONDecoder().decode(DashboardClockOptions.self, from: Data(#"{"timeZone":"Asia/Tokyo"}"#.utf8))
        #expect(tokyo.timeZone == "Asia/Tokyo")
        #expect(tokyo.resolvedTimeZone.identifier == "Asia/Tokyo")
        #expect(DashboardClockOptions(timeZone: "Mars/Olympus").resolvedTimeZone == .current)
        let none = try JSONDecoder().decode(DashboardClockOptions.self, from: Data(#"{"timeZone":5}"#.utf8))
        #expect(none.timeZone == nil)
        let written = String(decoding: try JSONEncoder().encode(DashboardClockOptions()), as: UTF8.self)
        #expect(!written.contains("timeZone"))
    }
}
