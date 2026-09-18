# Bento dashboard, part 1: core model and geometry — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the UI-free core of the bento dashboard: widget catalog, pages, migration from the 0.1.x dashboard, settings fields, geometry (validity, snapping, scale).

**Architecture:** Everything lives in `Sources/ApolloShellCore` as plain value types and pure functions with Swift Testing tests. Nothing in the app target changes in this part; the app keeps using `DashboardLayout` until part 2 (rendering) switches it over.

**Tech Stack:** Swift 6 (strict concurrency), Swift Testing, SwiftPM, macOS 26 SDK via Command Line Tools.

**Spec:** `design/2026-09-18-bento-dashboard.md` (read it first).

## Global Constraints

- Work only in `~/projects/private/apolloshell-0.2` on branch `release/0.2`. Never push. Never run `./build.sh` (it replaces the user's installed app).
- Run tests with `./test.sh` (plain `swift test` fails with the Command Line Tools). Targeted: `./test.sh --filter <SuiteTypeName>`. Full run only at the end of a task group, not after every step (the suite has ~760 tests and loads the CPU).
- Reference page: 839 × 392 points, spacing 12 (`DashboardGeometry.width/height/spacing`). Never hard-code these three numbers; use the constants.
- Stable IDs written to `settings.json` are never renamed: widget IDs `weather user clock calendar resources media performance.cpu performance.gpu performance.storage performance.network performance.memory performance.battery weather.hero weather.hourly weather.daily media.player`; template IDs `overview media performance weather`.
- Code comments in German with ASCII spelling (ue, ae, oe, ss), like the rest of the code. UI strings in German with real umlauts; every new `String(localized:)` string needs an English line in `Support/Localization/en/Dashboard.strings`.
- Decoding is lenient everywhere (`c.lenient(...)`, `LenientList`): a broken entry falls back or drops out, it never fails the whole file.
- Commit after every task. Message style like the repo: one English imperative line ("Add the widget catalog"). No `Co-Authored-By` trailer, no session IDs.

## File structure

| File | Responsibility |
| --- | --- |
| `Sources/ApolloShellCore/DashboardLayout.swift` (modify) | `DashboardClockOptions.timeZone` |
| `Sources/ApolloShellCore/Weather.swift` (modify) | `WeatherFavorites: Codable` |
| `Sources/ApolloShellCore/WidgetCatalog.swift` (create) | `WidgetSurface`, `WidgetSize`, `WidgetKind`, `PerformancePageGeometry`, `WeatherPageGeometry` |
| `Sources/ApolloShellCore/WidgetInstance.swift` (create) | `WidgetFrame`, `WidgetOptions`, `WidgetInstance` |
| `Sources/ApolloShellCore/BentoGeometry.swift` (create) | validity, scale factor, snapping, drop frame |
| `Sources/ApolloShellCore/DashboardPages.swift` (create) | `PageTemplate`, `DashboardPage`, `DashboardPages` |
| `Sources/ApolloShellCore/DashboardPagesDefaults.swift` (create) | preset pages, migration from `DashboardLayout` |
| `Sources/ApolloShellCore/ShellSettings.swift` (modify) | `dashboardPages`, `dashboardScale` |
| `Support/Localization/en/Dashboard.strings` (modify) | new widget titles |
| `Tests/ApolloShellCoreTests/…` | one test file per new source file, plus additions |

---

### Task 1: Clock time zone and codable weather places

**Files:**
- Modify: `Sources/ApolloShellCore/DashboardLayout.swift` (struct `DashboardClockOptions`, around line 322)
- Modify: `Sources/ApolloShellCore/Weather.swift` (struct `WeatherFavorites`, lines ~32-140)
- Test: `Tests/ApolloShellCoreTests/DashboardLayoutTests.swift` (append), `Tests/ApolloShellCoreTests/WeatherFavoritesCodableTests.swift` (create)

**Interfaces:**
- Produces: `DashboardClockOptions.timeZone: String?`, `DashboardClockOptions.resolvedTimeZone: TimeZone`, `init(style:showDate:timeZone:)`; `WeatherFavorites: Codable` (same JSON shape as weather.json).

- [ ] **Step 1: Write the failing tests**

Append inside `struct DashboardLayoutTests` in `DashboardLayoutTests.swift`:

```swift
    // MARK: Uhr-Zeitzone (0.2)

    @Test("Uhr: Zeitzone lesen, unbekannte gilt als System, nil wird nicht geschrieben")
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
```

Create `WeatherFavoritesCodableTests.swift`:

```swift
import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Wetter-Orte als Teil von settings.json (0.2)")
struct WeatherFavoritesCodableTests {
    private let zurich = WeatherLocation(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                         name: "Zürich", latitude: 47.37, longitude: 8.54)
    private let chur = WeatherLocation(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                                       name: "Chur", latitude: 46.85, longitude: 9.53)

    @Test("Hin und zurueck: gleiche Orte, gleicher gewaehlter")
    func roundTrip() throws {
        let favorites = WeatherFavorites(locations: [zurich, chur], selectedID: chur.id)
        let data = try JSONEncoder().encode(favorites)
        #expect(try JSONDecoder().decode(WeatherFavorites.self, from: data) == favorites)
    }

    @Test("Gleiches Format wie weather.json")
    func sameShapeAsFile() throws {
        let favorites = WeatherFavorites(locations: [zurich], selectedID: zurich.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        #expect(try encoder.encode(favorites) == favorites.fileData())
    }

    @Test("Nachsichtig: Ort ausserhalb der Erde faellt weg, fehlende Wahl = erster")
    func lenient() throws {
        let json = #"{"favorites":[{"name":"X","latitude":95,"longitude":0},{"id":"00000000-0000-0000-0000-000000000002","name":"Chur","latitude":46.85,"longitude":9.53}]}"#
        let favorites = try JSONDecoder().decode(WeatherFavorites.self, from: Data(json.utf8))
        #expect(favorites.locations.map(\.name) == ["Chur"])
        #expect(favorites.selectedID == chur.id)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `./test.sh --filter DashboardLayoutTests` and `./test.sh --filter WeatherFavoritesCodableTests`
Expected: compile errors (`timeZone` unknown, `WeatherFavorites` not `Decodable`).

- [ ] **Step 3: Implement**

In `DashboardClockOptions` add the field, the initialiser parameter, the lenient read and the resolver:

```swift
    /// Zeitzone als IANA-Kennung ("Asia/Tokyo"), `nil` = die des Systems.
    /// Gibt es mehrere Uhren (0.2), zeigt so jede eine andere Stadt. Eine
    /// unbekannte Kennung gilt wie `nil`.
    public var timeZone: String?

    public init(style: Style = .stacked, showDate: Bool = false, timeZone: String? = nil) {
        self.style = style
        self.showDate = showDate
        self.timeZone = timeZone
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.style, into: &style)
        c.lenient(.showDate, into: &showDate)
        timeZone = c.lenient(.timeZone)
    }

    public var resolvedTimeZone: TimeZone {
        timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
    }
```

(Replace the existing `init(style:showDate:)` and `init(from:)`; the synthesized `CodingKeys`/`encode` pick up `timeZone` and omit it when `nil`.)

In `Weather.swift`, split `load(from:)` and `fileData()` so the file format is reachable from `Codable`. Inside `struct WeatherFavorites` replace the bodies:

```swift
    public static func load(from data: Data?) -> WeatherFavorites {
        guard let data, let file = try? JSONDecoder().decode(File.self, from: data) else { return .empty }
        return favorites(from: file)
    }

    /// Die Regeln von `load(from:)`, auch fuer `Codable` (0.2: Orte je Wetter-Widget).
    private static func favorites(from file: File) -> WeatherFavorites {
        if let favoriteFiles = file.favorites {
            let locations = favoriteFiles.compactMap(\.location)
            let selectedID = file.selectedID.flatMap { id in locations.contains { $0.id == id } ? id : nil }
                ?? locations.first?.id
            return WeatherFavorites(locations: locations, selectedID: selectedID)
        }
        // Migration: alte Datei mit genau einem Ort, ohne "favorites".
        guard let latitude = file.latitude, let longitude = file.longitude,
              (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { return .empty }
        let name = file.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let location = WeatherLocation(name: name.isEmpty ? "Standort" : name, latitude: latitude, longitude: longitude)
        return WeatherFavorites(locations: [location], selectedID: location.id)
    }

    private var file: File {
        File(favorites: locations.map { File.Location(id: $0.id, name: $0.name, latitude: $0.latitude, longitude: $0.longitude) },
             selectedID: selectedID, name: nil, latitude: nil, longitude: nil)
    }

    public func fileData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(file)) ?? Data()
    }
```

Keep the existing doc comments above `load` and `fileData`. Then add, in the same file right after the struct (same file so it can use the private members):

```swift
/// Dasselbe Format wie weather.json - so tragen Wetter-Widgets ihre eigenen
/// Orte in settings.json (0.2). Gelesen nach den Regeln von `load(from:)`.
extension WeatherFavorites: Codable {
    public init(from decoder: any Decoder) throws {
        self = Self.favorites(from: try File(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        try file.encode(to: encoder)
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `./test.sh --filter DashboardLayoutTests` and `./test.sh --filter WeatherFavoritesCodableTests`, then the existing weather tests `./test.sh --filter Weather`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ApolloShellCore/DashboardLayout.swift Sources/ApolloShellCore/Weather.swift Tests/ApolloShellCoreTests/DashboardLayoutTests.swift Tests/ApolloShellCoreTests/WeatherFavoritesCodableTests.swift
git commit -m "Give the clock a time zone and make weather places codable"
```

---

### Task 2: Widget catalog

**Files:**
- Create: `Sources/ApolloShellCore/WidgetCatalog.swift`
- Modify: `Support/Localization/en/Dashboard.strings`
- Test: `Tests/ApolloShellCoreTests/WidgetCatalogTests.swift`

**Interfaces:**
- Consumes: `DashboardCardKind` (`zones`, `width(in:)`, `title`, `symbol`), `DashboardCardWidth.minimum`, `DashboardGeometry`, `DashboardCards`, `DashboardPreset`.
- Produces:
  - `enum WidgetSurface: String, Codable { case dashboard, controlCentre }`
  - `struct WidgetSize { minWidth, maxWidth, height: Double; static fixed(_:_:); static flexible(_:_:_:); isFlexible; allows(width:height:) }`
  - `enum WidgetKind: String, CaseIterable, Codable, Identifiable` with cases `weather, user, clock, calendar, resources, media, performanceCPU, performanceGPU, performanceStorage, performanceNetwork, performanceMemory, performanceBattery, weatherHero, weatherHourly, weatherDaily, mediaPlayer`; `init(_ card: DashboardCardKind)`, `overviewCard`, `title`, `symbol`, `home`, `sizes`, `smallestSize`, `allows(width:height:)`, `usesPlaces`, `usesMedia`, `isPerformance`
  - `enum PerformancePageGeometry { batteryWidth, networkWidth, bottomHeight, heroHeight, leftWidth(hasBattery:), heroWidths(hasBattery:) -> [Double], sideWidths(hasBattery:) -> [Double] }`
  - `enum WeatherPageGeometry { heroHeight, hourlyHeight, spacing, dailyHeight }`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Widget-Katalog: Kennungen und Groessen von vor 0.2")
struct WidgetCatalogTests {
    private func text(_ sizes: [WidgetSize]) -> String {
        sizes.map { s in s.isFlexible ? "\(Int(s.minWidth))-\(Int(s.maxWidth))x\(Int(s.height))" : "\(Int(s.minWidth))x\(Int(s.height))" }
            .joined(separator: " ")
    }

    @Test("Kennungen stehen in settings.json und aendern sich nie")
    func rawValues() {
        #expect(WidgetKind.allCases.map(\.rawValue) == [
            "weather", "user", "clock", "calendar", "resources", "media",
            "performance.cpu", "performance.gpu", "performance.storage", "performance.network",
            "performance.memory", "performance.battery",
            "weather.hero", "weather.hourly", "weather.daily", "media.player",
        ])
    }

    @Test("Jede Karte der Uebersicht ist ein Widget mit derselben Kennung")
    func cardsMap() {
        for card in DashboardCardKind.allCases {
            #expect(WidgetKind(card).overviewCard == card)
        }
    }

    @Test("Groessen der Uebersicht", arguments: [
        (WidgetKind.weather, "275-839x130 200-839x250 200-839x392"),
        (.user, "230-839x130 200-839x250 200-839x392"),
        (.clock, "110-839x130 110-839x250 110-839x392"),
        (.calendar, "300-839x250 300-839x392"),
        (.resources, "230-839x130 90-839x250 90-839x392"),
        (.media, "300-839x130 200-839x250 200-839x392"),
    ])
    func overviewSizes(kind: WidgetKind, expected: String) {
        #expect(text(kind.sizes) == expected)
    }

    @Test("Groessen der Seiten Leistung, Wetter, Medien", arguments: [
        (WidgetKind.performanceCPU, "343-414x191"),
        (.performanceGPU, "343-414x191"),
        (.performanceStorage, "169-240x189"),
        (.performanceNetwork, "335x189"),
        (.performanceMemory, "169-240x189"),
        (.performanceBattery, "129x392"),
        (.weatherHero, "839x116"),
        (.weatherHourly, "839x108"),
        (.weatherDaily, "839x144"),
        (.mediaPlayer, "839x392"),
    ])
    func pageSizes(kind: WidgetKind, expected: String) {
        #expect(text(kind.sizes) == expected)
    }

    @Test("Jede Karte jeder Vorlage und jedes Rasters von vor 0.2 hat eine erlaubte Groesse")
    func placementsAreAllowed() {
        var layouts = DashboardPreset.allCases.map(\.layout.cards)
        layouts += [
            DashboardCards(top: [.weather], bottom: [], side: []),
            DashboardCards(top: [], bottom: [.clock, .resources], side: []),
            DashboardCards(top: [], bottom: [], side: [.media]),
            DashboardCards(top: [.resources, .clock], bottom: [.media, .weather, .user], side: [.calendar]),
        ]
        for cards in layouts {
            for placement in DashboardGeometry.placements(for: cards) {
                let kind = WidgetKind(placement.card.kind)
                #expect(kind.allows(width: placement.frame.width, height: placement.frame.height),
                        "\(kind.rawValue) \(placement.frame)")
            }
        }
    }

    @Test("Kleinste Groesse nach Flaeche")
    func smallest() {
        #expect(WidgetKind.clock.smallestSize == .flexible(110, 839, 130))
        #expect(WidgetKind.resources.smallestSize == .flexible(90, 839, 250))
        #expect(WidgetKind.mediaPlayer.smallestSize == .fixed(839, 392))
    }

    @Test("Heimat, Orte, Medien")
    func flags() {
        #expect(WidgetKind.allCases.allSatisfy { $0.home == .dashboard })
        #expect(WidgetKind.allCases.filter(\.usesPlaces) == [.weather, .weatherHero, .weatherHourly, .weatherDaily])
        #expect(WidgetKind.allCases.filter(\.usesMedia) == [.media, .mediaPlayer])
        #expect(WidgetKind.allCases.filter(\.isPerformance).count == 6)
    }

    @Test("Masse der Seite Leistung: mit Akku schmaler")
    func performanceGeometry() {
        #expect(PerformancePageGeometry.heroHeight == 191)
        #expect(PerformancePageGeometry.heroWidths(hasBattery: true) == [343, 343])
        #expect(PerformancePageGeometry.heroWidths(hasBattery: false) == [413, 414])
        #expect(PerformancePageGeometry.sideWidths(hasBattery: true) == [169, 170])
        #expect(PerformancePageGeometry.sideWidths(hasBattery: false) == [240, 240])
        #expect(WeatherPageGeometry.dailyHeight == 144)
    }
}
```

(`DashboardCards` drops what 0.1.x would not allow, e.g. the calendar in the column, so whatever survives in these extra layouts is a real 0.1.x layout.)

- [ ] **Step 2: Run to see it fail**

Run: `./test.sh --filter WidgetCatalogTests`
Expected: compile error, `WidgetKind` unknown.

- [ ] **Step 3: Implement `WidgetCatalog.swift`**

```swift
import Foundation

// Katalog der Widgets fuer das Bento-Dashboard (0.2, siehe
// design/2026-09-18-bento-dashboard.md). Jedes Widget ist hier einmal
// beschrieben: Kennung, Name, Symbol, Heimat, erlaubte Groessen. Die Groessen
// sind genau die, die das Dashboard vor 0.2 zeichnen konnte.

/// Wo ein Widget zuhause ist. Ausserhalb der Heimat nur als erweiterte
/// Option in Nexus, dort nicht optimiert.
public enum WidgetSurface: String, Codable, CaseIterable, Sendable {
    case dashboard, controlCentre
}

/// Eine erlaubte Groesse in Referenzpunkten (Seite 839 x 392). Feste Breite:
/// `minWidth == maxWidth`. Die Hoehe ist immer fest.
public struct WidgetSize: Equatable, Hashable, Sendable {
    public var minWidth: Double
    public var maxWidth: Double
    public var height: Double

    public init(minWidth: Double, maxWidth: Double, height: Double) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.height = height
    }

    public static func fixed(_ width: Double, _ height: Double) -> WidgetSize {
        WidgetSize(minWidth: width, maxWidth: width, height: height)
    }

    public static func flexible(_ minWidth: Double, _ maxWidth: Double, _ height: Double) -> WidgetSize {
        WidgetSize(minWidth: minWidth, maxWidth: maxWidth, height: height)
    }

    public var isFlexible: Bool { maxWidth > minWidth }

    public func allows(width: Double, height: Double) -> Bool {
        height == self.height && width >= minWidth && width <= maxWidth
    }
}

/// Alle Widgets. Rohwert steht in settings.json - nie umbenennen. Die sechs
/// Karten der Uebersicht behalten die Kennungen von `DashboardCardKind`.
public enum WidgetKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case weather, user, clock, calendar, resources, media
    case performanceCPU = "performance.cpu"
    case performanceGPU = "performance.gpu"
    case performanceStorage = "performance.storage"
    case performanceNetwork = "performance.network"
    case performanceMemory = "performance.memory"
    case performanceBattery = "performance.battery"
    case weatherHero = "weather.hero"
    case weatherHourly = "weather.hourly"
    case weatherDaily = "weather.daily"
    case mediaPlayer = "media.player"

    public var id: Self { self }

    public init(_ card: DashboardCardKind) {
        // Gleiche Rohwerte, der Test `cardsMap` haelt das fest.
        self = WidgetKind(rawValue: card.rawValue)!
    }

    /// Die Karte von vor 0.2, falls das Widget eine ist.
    public var overviewCard: DashboardCardKind? { DashboardCardKind(rawValue: rawValue) }

    public var title: String {
        if let card = overviewCard { return card.title }
        return switch self {
        case .performanceCPU: "CPU"
        case .performanceGPU: "GPU"
        case .performanceStorage: String(localized: "Speicher")
        case .performanceNetwork: String(localized: "Netzwerk")
        case .performanceMemory: String(localized: "Arbeitsspeicher")
        case .performanceBattery: String(localized: "Akku")
        case .weatherHero: String(localized: "Wetterübersicht")
        case .weatherHourly: String(localized: "Stündlich")
        case .weatherDaily: String(localized: "Nächste Tage")
        case .mediaPlayer: String(localized: "Wiedergabe")
        case .weather, .user, .clock, .calendar, .resources, .media: ""
        }
    }

    public var symbol: String {
        if let card = overviewCard { return card.symbol }
        return switch self {
        case .performanceCPU: "cpu"
        case .performanceGPU: "square.stack.3d.up"
        case .performanceStorage: "internaldrive"
        case .performanceNetwork: "network"
        case .performanceMemory: "memorychip"
        case .performanceBattery: "battery.75percent"
        case .weatherHero: "cloud.sun"
        case .weatherHourly: "clock"
        case .weatherDaily: "calendar"
        case .mediaPlayer: "play.rectangle"
        case .weather, .user, .clock, .calendar, .resources, .media: "questionmark"
        }
    }

    /// Alle heutigen Widgets gehoeren ins Dashboard; das Control Centre
    /// bekommt seine eigenen erst mit dem Editor fuer alle Flaechen.
    public var home: WidgetSurface { .dashboard }

    /// Wetter-Widgets tragen ihre eigene Liste an Orten (`WidgetOptions.places`).
    public var usesPlaces: Bool {
        switch self {
        case .weather, .weatherHero, .weatherHourly, .weatherDaily: true
        default: false
        }
    }

    public var usesMedia: Bool { self == .media || self == .mediaPlayer }

    public var isPerformance: Bool { rawValue.hasPrefix("performance.") }

    public var sizes: [WidgetSize] {
        if let card = overviewCard { return Self.overviewSizes(card) }
        let p = PerformancePageGeometry.self
        let w = DashboardGeometry.width
        switch self {
        case .performanceCPU, .performanceGPU:
            return [.flexible(p.heroWidths(hasBattery: true).min()!, p.heroWidths(hasBattery: false).max()!, p.heroHeight)]
        case .performanceStorage, .performanceMemory:
            return [.flexible(p.sideWidths(hasBattery: true).min()!, p.sideWidths(hasBattery: false).max()!, p.bottomHeight)]
        case .performanceNetwork: return [.fixed(p.networkWidth, p.bottomHeight)]
        case .performanceBattery: return [.fixed(p.batteryWidth, DashboardGeometry.height)]
        case .weatherHero: return [.fixed(w, WeatherPageGeometry.heroHeight)]
        case .weatherHourly: return [.fixed(w, WeatherPageGeometry.hourlyHeight)]
        case .weatherDaily: return [.fixed(w, WeatherPageGeometry.dailyHeight)]
        case .mediaPlayer: return [.fixed(w, DashboardGeometry.height)]
        case .weather, .user, .clock, .calendar, .resources, .media: return []
        }
    }

    /// Kleinste Groesse nach Flaeche (Mindestbreite x Hoehe) - so kommt ein
    /// neues Widget aus Nexus auf die Seite.
    public var smallestSize: WidgetSize {
        sizes.min { $0.minWidth * $0.height < $1.minWidth * $1.height }!
    }

    public func allows(width: Double, height: Double) -> Bool {
        sizes.contains { $0.allows(width: width, height: height) }
    }

    /// Karten der Uebersicht: jede Breite von der kleinsten ihrer Plaetze bis
    /// zur ganzen Seite - eine Reihe ohne flexible Karte wurde vor 0.2 im
    /// Verhaeltnis gestreckt, eine Spaltenkarte allein fuellte die Seite. Die
    /// Hoehen sind die ihrer Plaetze: obere Reihe 130, untere 250, eine Reihe
    /// allein oder die Spalte 392.
    static func overviewSizes(_ card: DashboardCardKind) -> [WidgetSize] {
        let g = DashboardGeometry.self
        let bottomHeight = g.height - g.topHeight - g.spacing
        var minimumByHeight: [Double: Double] = [:]
        for zone in card.zones {
            let minimum = card.width(in: zone).minimum
            let heights: [Double] = switch zone {
            case .top: [g.topHeight, g.height]
            case .bottom: [bottomHeight, g.height]
            case .side: [g.height]
            }
            for height in heights {
                minimumByHeight[height] = min(minimumByHeight[height] ?? minimum, minimum)
            }
        }
        return minimumByHeight.keys.sorted().map { .flexible(minimumByHeight[$0]!, g.width, $0) }
    }
}

/// Masse der Seite Leistung, Caelestias Werte x 0,858 (vor 0.2 fest in
/// PerformanceView). Links CPU und GPU ueber Speicher, Netzwerk,
/// Arbeitsspeicher, rechts der Akku - ohne Akku wird links alles breiter.
public enum PerformancePageGeometry {
    public static let batteryWidth: Double = 129   // 150 x 0,858
    public static let networkWidth: Double = 335   // 390 x 0,858
    public static let bottomHeight: Double = 189   // 220 x 0,858
    public static var heroHeight: Double { DashboardGeometry.height - bottomHeight - DashboardGeometry.spacing }

    public static func leftWidth(hasBattery: Bool) -> Double {
        hasBattery ? DashboardGeometry.width - DashboardGeometry.spacing - batteryWidth : DashboardGeometry.width
    }

    /// CPU und GPU nebeneinander.
    public static func heroWidths(hasBattery: Bool) -> [Double] {
        split(leftWidth(hasBattery: hasBattery) - DashboardGeometry.spacing)
    }

    /// Speicher und Arbeitsspeicher links und rechts vom Netzwerk.
    public static func sideWidths(hasBattery: Bool) -> [Double] {
        split(leftWidth(hasBattery: hasBattery) - networkWidth - 2 * DashboardGeometry.spacing)
    }

    /// Halbieren wie `DashboardGeometry.widths`: abgerundet, der Rest an den zweiten.
    static func split(_ total: Double) -> [Double] {
        let first = (total / 2).rounded(.down)
        return [first, total - first]
    }
}

/// Masse der Seite Wetter (vor 0.2 fest in WeatherTab).
public enum WeatherPageGeometry {
    public static let heroHeight: Double = 116
    public static let hourlyHeight: Double = 108
    public static let spacing: Double = 12
    public static var dailyHeight: Double { DashboardGeometry.height - heroHeight - hourlyHeight - 2 * spacing }
}
```

Append to `Support/Localization/en/Dashboard.strings` only the keys that are not in that file yet (check with `grep '^"Speicher"' Support/Localization/en/Dashboard.strings` etc.). Expected new lines:

```
"Wetterübersicht" = "Weather overview";
"Stündlich" = "Hourly";
"Nächste Tage" = "Next days";
```

- [ ] **Step 4: Run to see it pass**

Run: `./test.sh --filter WidgetCatalogTests`
Expected: PASS. If `placementsAreAllowed` fails, print the failing frame; the rule in `overviewSizes` is wrong, not the old geometry.

- [ ] **Step 5: Commit**

```bash
git add Sources/ApolloShellCore/WidgetCatalog.swift Tests/ApolloShellCoreTests/WidgetCatalogTests.swift Support/Localization/en/Dashboard.strings
git commit -m "Add the widget catalog with the sizes the dashboard has today"
```

---

### Task 3: Widget instances

**Files:**
- Create: `Sources/ApolloShellCore/WidgetInstance.swift`
- Test: `Tests/ApolloShellCoreTests/WidgetInstanceTests.swift`

**Interfaces:**
- Consumes: `WidgetKind`, option structs from `DashboardLayout.swift`, `WeatherFavorites: Codable`, `DashboardRect`.
- Produces:
  - `struct WidgetFrame: Codable, Hashable { x, y, width, height: Double; init(x:y:width:height:); init(_ rect: DashboardRect); maxX; maxY; rounded() }`
  - `struct WidgetOptions: Codable, Equatable { weather, user, clock, calendar, resources, media: …Options?; places: WeatherFavorites?; static defaults(for:places:) }`
  - `struct WidgetInstance: Codable, Equatable, Identifiable { id: UUID; kind; frame; options; init(id:kind:frame:options:) }`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Widget auf einer Seite: Rahmen, Optionen, nachsichtiges Lesen")
struct WidgetInstanceTests {
    private func decode(_ json: String) -> WidgetInstance? {
        try? JSONDecoder().decode(WidgetInstance.self, from: Data(json.utf8))
    }

    @Test("Vorgaben je Art: nur das eigene Feld, Wetter mit Orten")
    func defaults() {
        let place = WeatherLocation(name: "Chur", latitude: 46.85, longitude: 9.53)
        let places = WeatherFavorites(locations: [place], selectedID: place.id)
        let weather = WidgetOptions.defaults(for: .weather, places: places)
        #expect(weather.weather == DashboardWeatherOptions())
        #expect(weather.places == places)
        #expect(weather.clock == nil)
        #expect(WidgetOptions.defaults(for: .weatherDaily, places: places).places == places)
        #expect(WidgetOptions.defaults(for: .clock).clock == DashboardClockOptions())
        #expect(WidgetOptions.defaults(for: .performanceCPU) == WidgetOptions())
    }

    @Test("Hin und zurueck")
    func roundTrip() throws {
        let widget = WidgetInstance(kind: .clock, frame: WidgetFrame(x: 0, y: 142, width: 110, height: 250),
                                    options: WidgetOptions(clock: DashboardClockOptions(timeZone: "Asia/Tokyo")))
        let data = try JSONEncoder().encode(widget)
        #expect(try JSONDecoder().decode(WidgetInstance.self, from: data) == widget)
        #expect(!String(decoding: data, as: UTF8.self).contains("\"weather\""))
    }

    @Test("Unbekannte Art oder fehlender Rahmen: nicht lesbar")
    func rejects() {
        #expect(decode(#"{"kind":"toaster","frame":{"x":0,"y":0,"width":90,"height":250}}"#) == nil)
        #expect(decode(#"{"kind":"clock"}"#) == nil)
        #expect(decode(#"{"kind":"clock","frame":{"x":0,"y":0}}"#) == nil)
    }

    @Test("Fehlende Kennung wird neu, kaputte Optionen werden Vorgaben")
    func lenient() {
        let widget = decode(#"{"kind":"clock","frame":{"x":0,"y":0,"width":110,"height":250},"options":7}"#)
        #expect(widget?.kind == .clock)
        #expect(widget?.options == WidgetOptions.defaults(for: .clock))
        let partial = decode(#"{"kind":"clock","frame":{"x":0,"y":0,"width":110,"height":250},"options":{"clock":{"showDate":true},"user":5}}"#)
        #expect(partial?.options.clock?.showDate == true)
        #expect(partial?.options.user == nil)
    }

    @Test("Runden auf ganze Punkte")
    func rounding() {
        #expect(WidgetFrame(x: 10.4, y: 10.6, width: 99.5, height: 130).rounded() == WidgetFrame(x: 10, y: 11, width: 100, height: 130))
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `./test.sh --filter WidgetInstanceTests`
Expected: compile error, `WidgetInstance` unknown.

- [ ] **Step 3: Implement `WidgetInstance.swift`**

```swift
import Foundation

/// Rahmen eines Widgets auf der Seite, in Referenzpunkten ab der Ecke oben
/// links (Seite 839 x 392, `DashboardGeometry`). Gespeichert als ganze Punkte.
public struct WidgetFrame: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: DashboardRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    /// Ziehen liefert Bruchteile; gespeichert wird in ganzen Punkten.
    public func rounded() -> WidgetFrame {
        WidgetFrame(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }
}

/// Optionen eines Widgets. Jede Art liest nur ihr eigenes Feld (die Uhr
/// `clock`, ...), die uebrigen bleiben `nil` und stehen nicht in der Datei.
/// Fehlt das Feld der eigenen Art, gelten deren Vorgaben (`?? .init()` in
/// der Ansicht).
public struct WidgetOptions: Codable, Equatable, Sendable {
    public var weather: DashboardWeatherOptions?
    public var user: DashboardUserOptions?
    public var clock: DashboardClockOptions?
    public var calendar: DashboardCalendarOptions?
    public var resources: DashboardResourcesOptions?
    public var media: DashboardMediaOptions?
    /// Orte der Wetter-Widgets, je Widget eine eigene Liste.
    public var places: WeatherFavorites?

    public init(weather: DashboardWeatherOptions? = nil, user: DashboardUserOptions? = nil,
                clock: DashboardClockOptions? = nil, calendar: DashboardCalendarOptions? = nil,
                resources: DashboardResourcesOptions? = nil, media: DashboardMediaOptions? = nil,
                places: WeatherFavorites? = nil) {
        self.weather = weather
        self.user = user
        self.clock = clock
        self.calendar = calendar
        self.resources = resources
        self.media = media
        self.places = places
    }

    /// Vorgaben einer Art. Wetter-Widgets bekommen `places` (beim Umzug die
    /// Favoriten aus weather.json).
    public static func defaults(for kind: WidgetKind, places: WeatherFavorites = .empty) -> WidgetOptions {
        var options = WidgetOptions()
        switch kind {
        case .weather:
            options.weather = DashboardWeatherOptions()
            options.places = places
        case .weatherHero, .weatherHourly, .weatherDaily: options.places = places
        case .user: options.user = DashboardUserOptions()
        case .clock: options.clock = DashboardClockOptions()
        case .calendar: options.calendar = DashboardCalendarOptions()
        case .resources: options.resources = DashboardResourcesOptions()
        case .media: options.media = DashboardMediaOptions()
        case .performanceCPU, .performanceGPU, .performanceStorage, .performanceNetwork,
             .performanceMemory, .performanceBattery, .mediaPlayer:
            break
        }
        return options
    }

    private enum CodingKeys: String, CodingKey { case weather, user, clock, calendar, resources, media, places }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weather = c.lenient(.weather)
        user = c.lenient(.user)
        clock = c.lenient(.clock)
        calendar = c.lenient(.calendar)
        resources = c.lenient(.resources)
        media = c.lenient(.media)
        places = c.lenient(.places)
    }
}

/// Ein Widget auf einer Seite. Dieselbe Art darf mehrfach vorkommen, jede
/// mit eigenen Optionen (zwei Uhren, zwei Wetter).
public struct WidgetInstance: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: WidgetKind
    public var frame: WidgetFrame
    public var options: WidgetOptions

    public init(id: UUID = UUID(), kind: WidgetKind, frame: WidgetFrame, options: WidgetOptions? = nil) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.options = options ?? .defaults(for: kind)
    }

    private enum CodingKeys: String, CodingKey { case id, kind, frame, options }

    /// Unbekannte Art oder fehlender Rahmen: Fehler - die Seite uebergeht das
    /// Widget dann. Fehlende Kennung: eine neue; kaputte Optionen: Vorgaben.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw: String = c.lenient(.kind), let kind = WidgetKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unbekanntes Widget")
        }
        guard let frame: WidgetFrame = c.lenient(.frame) else {
            throw DecodingError.dataCorruptedError(forKey: .frame, in: c, debugDescription: "Rahmen fehlt")
        }
        self.init(id: c.lenient(.id) ?? UUID(), kind: kind, frame: frame, options: c.lenient(.options))
    }
}
```

- [ ] **Step 4: Run to see it pass**

Run: `./test.sh --filter WidgetInstanceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ApolloShellCore/WidgetInstance.swift Tests/ApolloShellCoreTests/WidgetInstanceTests.swift
git commit -m "Add widget instances with frame and per-widget options"
```

---

### Task 4: Geometry — validity and scale

**Files:**
- Create: `Sources/ApolloShellCore/BentoGeometry.swift`
- Test: `Tests/ApolloShellCoreTests/BentoGeometryTests.swift`

**Interfaces:**
- Consumes: `WidgetFrame`, `WidgetKind.allows(width:height:)`, `DashboardGeometry`.
- Produces: `enum BentoGeometry` with `pageWidth`, `pageHeight`, `spacing`, `snapDistance` (8), `referenceScreenWidth` (1512), `automaticRange` (0.85...1.5), `userScaleRange` (0.7...1.5), `isInside(_:)`, `tooClose(_:_:)`, `isValid(_:kind:others:)`, `clampedUserScale(_:)`, `scale(screenWidth:availableHeight:contentHeight:userScale:)`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Bento-Geometrie: gueltige Lage und Massstab")
struct BentoGeometryTests {
    private func f(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> WidgetFrame {
        WidgetFrame(x: x, y: y, width: w, height: h)
    }

    @Test("Auf der Seite")
    func inside() {
        #expect(BentoGeometry.isInside(f(0, 0, 839, 392)))
        #expect(!BentoGeometry.isInside(f(-1, 0, 100, 130)))
        #expect(!BentoGeometry.isInside(f(740, 0, 100, 130)))
        #expect(!BentoGeometry.isInside(f(0, 263, 110, 130)))
    }

    @Test("Genau 12 Punkte Abstand ist erlaubt, 11 nicht, schraeg versetzt zaehlt nicht")
    func spacing() {
        let weather = f(0, 0, 275, 130)
        #expect(!BentoGeometry.tooClose(weather, f(287, 0, 340, 130)))
        #expect(BentoGeometry.tooClose(weather, f(286, 0, 340, 130)))
        #expect(!BentoGeometry.tooClose(weather, f(0, 142, 110, 250)))
        #expect(BentoGeometry.tooClose(weather, f(0, 141, 110, 250)))
        #expect(BentoGeometry.tooClose(weather, f(280, 136, 100, 250)))            // 5 in x, 6 in y: zu nah
        #expect(!BentoGeometry.tooClose(weather, f(300, 200, 100, 130)))           // 25 in x: frei
        #expect(BentoGeometry.tooClose(weather, f(100, 50, 50, 50)))               // ueberlappt
    }

    @Test("Gueltig: auf der Seite, erlaubte Groesse, Abstand")
    func valid() {
        let others = [f(0, 0, 275, 130)]
        #expect(BentoGeometry.isValid(f(0, 142, 110, 250), kind: .clock, others: others))
        #expect(!BentoGeometry.isValid(f(0, 142, 100, 250), kind: .clock, others: others))   // zu schmal
        #expect(!BentoGeometry.isValid(f(0, 142, 110, 200), kind: .clock, others: others))   // Hoehe gibt es nicht
        #expect(!BentoGeometry.isValid(f(0, 130, 110, 250), kind: .clock, others: others))   // zu nah
    }

    @Test("Massstab: Automatik nach Breite, Regler, Hoehe begrenzt", arguments: [
        (1512.0, 2000.0, 1.0, 1.0),
        (2560, 2000, 1.0, 1.5),
        (1280, 2000, 1.0, 0.85),
        (1512, 2000, 1.2, 1.2),
        (2560, 2000, 1.5, 2.25),
        (1512, 400, 1.0, 400.0 / 460.0),
        (1512, 2000, 9.0, 1.5),
        (1512, 2000, .nan, 1.0),
    ])
    func scale(screenWidth: Double, availableHeight: Double, user: Double, expected: Double) {
        let value = BentoGeometry.scale(screenWidth: screenWidth, availableHeight: availableHeight,
                                        contentHeight: 460, userScale: user)
        #expect(abs(value - expected) < 0.0001)
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `./test.sh --filter BentoGeometryTests`
Expected: compile error, `BentoGeometry` unknown.

- [ ] **Step 3: Implement `BentoGeometry.swift`**

```swift
import Foundation

/// Geometrie der Bento-Seiten: gueltige Lage, Einrasten, Massstab. Reine
/// Funktionen in Referenzpunkten (Seite 839 x 392, `DashboardGeometry`).
/// Keine Zellen: Caelestias Masse (130, 250, 275, 110 ...) passen in kein
/// gleichmaessiges Raster, Ordnung kommt vom Einrasten.
public enum BentoGeometry {
    public static let pageWidth = DashboardGeometry.width
    public static let pageHeight = DashboardGeometry.height
    /// Mindestabstand zweier Widgets, Caelestias Rasterabstand.
    public static let spacing = DashboardGeometry.spacing
    /// Naeher als das: das Widget springt aufs Ziel.
    public static let snapDistance: Double = 8

    // MARK: Gueltig

    public static func isInside(_ frame: WidgetFrame) -> Bool {
        frame.x >= 0 && frame.y >= 0 && frame.maxX <= pageWidth && frame.maxY <= pageHeight
    }

    /// Naeher als `spacing` in beiden Achsen, Ueberlappung eingeschlossen.
    /// Genau `spacing` Abstand ist erlaubt; schraeg versetzt zaehlt nur, wenn
    /// beide Achsen zu nah sind.
    public static func tooClose(_ a: WidgetFrame, _ b: WidgetFrame) -> Bool {
        a.x < b.maxX + spacing && b.x < a.maxX + spacing
            && a.y < b.maxY + spacing && b.y < a.maxY + spacing
    }

    public static func isValid(_ frame: WidgetFrame, kind: WidgetKind, others: [WidgetFrame]) -> Bool {
        isInside(frame) && kind.allows(width: frame.width, height: frame.height)
            && !others.contains { tooClose(frame, $0) }
    }

    // MARK: Massstab

    /// Breite des 14-Zoll-MacBooks: dort Faktor 1, alles wie vor 0.2.
    public static let referenceScreenWidth: Double = 1512
    public static let automaticRange: ClosedRange<Double> = 0.85...1.5
    /// Der Regler in Nexus.
    public static let userScaleRange: ClosedRange<Double> = 0.7...1.5

    public static func clampedUserScale(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, userScaleRange.lowerBound), userScaleRange.upperBound)
    }

    /// Massstab fuer einen Bildschirm: Automatik nach Breite mal Regler,
    /// hoechstens so gross, dass `contentHeight` (das ganze Dashboard in
    /// Referenzgroesse, mit Seitenleiste oben) in `availableHeight` passt.
    public static func scale(screenWidth: Double, availableHeight: Double, contentHeight: Double,
                             userScale: Double) -> Double {
        let automatic = min(max(screenWidth / referenceScreenWidth, automaticRange.lowerBound), automaticRange.upperBound)
        let wanted = automatic * clampedUserScale(userScale)
        guard contentHeight > 0 else { return wanted }
        return min(wanted, availableHeight / contentHeight)
    }
}
```

- [ ] **Step 4: Run to see it pass**

Run: `./test.sh --filter BentoGeometryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ApolloShellCore/BentoGeometry.swift Tests/ApolloShellCoreTests/BentoGeometryTests.swift
git commit -m "Add bento geometry: valid frames and the dashboard scale"
```

---

### Task 5: Geometry — snapping, resizing, dropping

**Files:**
- Modify: `Sources/ApolloShellCore/BentoGeometry.swift`
- Test: `Tests/ApolloShellCoreTests/BentoGeometryTests.swift` (append a second suite in the same file)

**Interfaces:**
- Consumes: Task 4.
- Produces: `BentoGeometry.snapMove(_ proposed: WidgetFrame, others: [WidgetFrame]) -> WidgetFrame`, `BentoGeometry.snapResize(_ frame: WidgetFrame, kind: WidgetKind, proposedWidth: Double, proposedHeight: Double, others: [WidgetFrame]) -> WidgetFrame`, `BentoGeometry.dropFrame(kind: WidgetKind, x: Double, y: Double, others: [WidgetFrame]) -> WidgetFrame`.

- [ ] **Step 1: Write the failing tests**

Append to `BentoGeometryTests.swift`:

```swift
@Suite("Bento-Geometrie: Einrasten")
struct BentoSnapTests {
    private func f(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> WidgetFrame {
        WidgetFrame(x: x, y: y, width: w, height: h)
    }
    private let weather = WidgetFrame(x: 0, y: 0, width: 275, height: 130)

    @Test("Ziehen: Seitenrand, Flucht, 12 Punkte daneben, sonst frei", arguments: [
        (WidgetFrame(x: 5, y: 300, width: 100, height: 50), 0.0, 300.0),     // linker Rand (y frei)
        (WidgetFrame(x: 636, y: 3, width: 200, height: 130), 639, 0),        // rechter Rand, oberer Rand
        (WidgetFrame(x: 290, y: 4, width: 200, height: 130), 287, 0),        // 12 neben dem Wetter
        (WidgetFrame(x: 400.4, y: 250.6, width: 100, height: 50), 400, 251), // kein Ziel: nur gerundet
        (WidgetFrame(x: 3, y: 146, width: 110, height: 250), 0, 142),        // Flucht links, 12 unter dem Wetter
    ])
    func move(proposed: WidgetFrame, x: Double, y: Double) {
        let snapped = BentoGeometry.snapMove(proposed, others: [weather])
        #expect(snapped.x == x)
        #expect(snapped.y == y)
        #expect(snapped.width == proposed.width.rounded())
    }

    @Test("Ziehen: das naechste Ziel gewinnt")
    func nearestWins() {
        // Rechte Kante buendig mit dem Wetter (x = 175) liegt 2 weg, alles andere weiter.
        let snapped = BentoGeometry.snapMove(f(177, 300, 100, 50), others: [weather])
        #expect(snapped.x == 175)
    }

    @Test("Groesse: Hoehe springt, Breite bleibt in der Spanne und rastet ein")
    func resize() {
        let clock = f(0, 142, 110, 250)
        // Hoehe 260 -> 250, Breite 115 frei (kein Ziel naeher als 8)
        #expect(BentoGeometry.snapResize(clock, kind: .clock, proposedWidth: 115, proposedHeight: 260, others: []) == f(0, 142, 115, 250))
        // Hoehe 380 -> 392 passt nicht mehr auf die Seite; die Funktion rastet nur, gueltig prueft isValid
        #expect(BentoGeometry.snapResize(clock, kind: .clock, proposedWidth: 110, proposedHeight: 380, others: []).height == 392)
        // Breite unter dem Minimum -> Minimum
        #expect(BentoGeometry.snapResize(clock, kind: .clock, proposedWidth: 40, proposedHeight: 250, others: []).width == 110)
        // Breite rastet 12 vor dem Nachbarn ein: Nachbar bei x = 300 -> Breite 288
        let neighbour = f(300, 142, 110, 250)
        #expect(BentoGeometry.snapResize(clock, kind: .clock, proposedWidth: 283, proposedHeight: 250, others: [neighbour]).width == 288)
        // Feste Groesse bleibt fest
        let network = f(0, 203, 335, 189)
        #expect(BentoGeometry.snapResize(network, kind: .performanceNetwork, proposedWidth: 400, proposedHeight: 150, others: []) == network)
    }

    @Test("Ablegen: kleinste Groesse, mittig unter dem Zeiger, eingerastet")
    func drop() {
        let frame = BentoGeometry.dropFrame(kind: .clock, x: 60, y: 208, others: [weather])
        #expect(frame == f(0, 142, 110, 130))   // 60-55 = 5 -> Rand 0; 208-65 = 143 -> 142 (12 unter dem Wetter)
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `./test.sh --filter BentoSnapTests`
Expected: compile error, `snapMove` unknown.

- [ ] **Step 3: Implement** — append inside `enum BentoGeometry`:

```swift
    // MARK: Einrasten

    /// Ziehen: je Achse springt das Widget aufs naechste Ziel naeher als
    /// `snapDistance` - Seitenrand, gleiche Flucht wie ein anderes Widget,
    /// oder genau `spacing` daneben. Ohne Ziel bleibt die Achse. Ergebnis
    /// auf ganze Punkte gerundet; ob es passt, sagt `isValid`.
    public static func snapMove(_ proposed: WidgetFrame, others: [WidgetFrame]) -> WidgetFrame {
        var frame = proposed
        frame.x = snap(frame.x, to: startCandidates(length: frame.width, page: pageWidth,
                                                    others: others.map { (start: $0.x, end: $0.maxX) }))
        frame.y = snap(frame.y, to: startCandidates(length: frame.height, page: pageHeight,
                                                    others: others.map { (start: $0.y, end: $0.maxY) }))
        return frame.rounded()
    }

    /// Groesse ziehen (Griff unten rechts, Ecke oben links bleibt): die Hoehe
    /// springt auf die naechste erlaubte, die Breite bleibt in der Spanne
    /// dieser Groesse und rastet bei flexiblen Widgets am Seitenrand und an
    /// Nachbarn ein (rechte Kanten buendig oder `spacing` vor dem Nachbarn).
    public static func snapResize(_ frame: WidgetFrame, kind: WidgetKind, proposedWidth: Double,
                                  proposedHeight: Double, others: [WidgetFrame]) -> WidgetFrame {
        guard let size = kind.sizes.min(by: { abs($0.height - proposedHeight) < abs($1.height - proposedHeight) })
        else { return frame }
        var width = min(max(proposedWidth, size.minWidth), size.maxWidth)
        if size.isFlexible {
            var candidates = [pageWidth - frame.x]
            for other in others {
                candidates += [other.x - spacing - frame.x, other.maxX - frame.x]
            }
            width = snap(width, to: candidates.filter { $0 >= size.minWidth && $0 <= size.maxWidth })
        }
        return WidgetFrame(x: frame.x, y: frame.y, width: width, height: size.height).rounded()
    }

    /// Neues Widget aus Nexus: kleinste Groesse, mittig unter dem Zeiger
    /// (`x`, `y` in Referenzpunkten), dann eingerastet wie beim Ziehen.
    public static func dropFrame(kind: WidgetKind, x: Double, y: Double, others: [WidgetFrame]) -> WidgetFrame {
        let size = kind.smallestSize
        let proposed = WidgetFrame(x: x - size.minWidth / 2, y: y - size.height / 2,
                                   width: size.minWidth, height: size.height)
        return snapMove(proposed, others: others)
    }

    /// Moegliche Anfaenge auf einer Achse: beide Seitenraender, dieselbe
    /// Flucht wie ein anderes Widget (Anfang an Anfang, Ende an Ende) und
    /// genau `spacing` davor oder dahinter.
    static func startCandidates(length: Double, page: Double, others: [(start: Double, end: Double)]) -> [Double] {
        var result = [0, page - length]
        for other in others {
            result += [other.start, other.end - length, other.end + spacing, other.start - spacing - length]
        }
        return result
    }

    static func snap(_ value: Double, to candidates: [Double]) -> Double {
        guard let best = candidates.min(by: { abs($0 - value) < abs($1 - value) }),
              abs(best - value) < snapDistance else { return value }
        return best
    }
```

- [ ] **Step 4: Run to see it pass**

Run: `./test.sh --filter BentoSnapTests` and `./test.sh --filter BentoGeometryTests`
Expected: PASS. If a table row fails, recompute the candidates by hand before changing the code; the test numbers are derived from the rules above.

- [ ] **Step 5: Commit**

```bash
git add Sources/ApolloShellCore/BentoGeometry.swift Tests/ApolloShellCoreTests/BentoGeometryTests.swift
git commit -m "Snap bento widgets to edges, neighbours and their sizes"
```

---

### Task 6: Pages

**Files:**
- Create: `Sources/ApolloShellCore/DashboardPages.swift`
- Test: `Tests/ApolloShellCoreTests/DashboardPagesTests.swift`

**Interfaces:**
- Consumes: `WidgetInstance`, `WidgetKind`, `BentoGeometry.isValid`, `DashboardTab`, `LenientList`, `Array.move(fromOffsets:toOffset:)` (Reorder.swift).
- Produces:
  - `enum PageTemplate: String, Codable, CaseIterable { overview, media, performance, weather; init(_ tab: DashboardTab); tab }`
  - `struct DashboardPage: Codable, Equatable, Identifiable { id, name, symbol, template: PageTemplate?; private(set) widgets; static defaultSymbol; init(id:name:symbol:template:widgets:); add(_:) -> Bool; setFrame(_:for:) -> Bool; setOptions(_:for:); removeWidget(id:); frames(excluding:); duplicated(name:); contains(_:) }`
  - `struct DashboardPages: Codable, Equatable { private(set) pages; init?(pages:); page(id:); update(_:); addPage(name:symbol:) -> ID; duplicatePage(id:name:) -> ID?; removePage(id:) -> Bool; renamePage(id:to:); setSymbol(_:forPage:); movePages(fromOffsets:toOffset:); restoreDefaults(from:); page(for:showing:); usesWeather; usesMedia }`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Dashboard-Seiten: Widgets auf der Seite, Seitenverwaltung, Lesen")
struct DashboardPagesTests {
    private func f(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> WidgetFrame {
        WidgetFrame(x: x, y: y, width: w, height: h)
    }
    private func clock(_ frame: WidgetFrame) -> WidgetInstance { WidgetInstance(kind: .clock, frame: frame) }

    @Test("Seite behaelt nur gueltige Widgets, in Reihenfolge")
    func normalizes() {
        let a = clock(f(0, 0, 110, 130))
        let tooClose = clock(f(115, 0, 110, 130))
        let wrongSize = clock(f(300, 0, 100, 130))
        let outside = clock(f(800, 0, 110, 130))
        let b = clock(f(122, 0, 110, 130))
        let page = DashboardPage(name: "X", symbol: "star", widgets: [a, tooClose, wrongSize, outside, b, a])
        #expect(page.widgets.map(\.id) == [a.id, b.id])
    }

    @Test("Widget hinzufuegen, verschieben, entfernen: Ungueltiges aendert nichts")
    func widgetEdits() {
        var page = DashboardPage(name: "X", symbol: "star")
        let a = clock(f(0, 0, 110, 130))
        #expect(page.add(a))
        #expect(!page.add(clock(f(100, 0, 110, 130))))
        #expect(page.setFrame(f(0, 0, 200, 250), for: a.id))
        #expect(!page.setFrame(f(0, 0, 50, 250), for: a.id))
        #expect(page.widgets[0].frame == f(0, 0, 200, 250))
        page.setOptions(WidgetOptions(clock: DashboardClockOptions(showDate: true)), for: a.id)
        #expect(page.widgets[0].options.clock?.showDate == true)
        page.removeWidget(id: a.id)
        #expect(page.widgets.isEmpty)
    }

    @Test("Seiten: nie leer, letzte nicht loeschbar, Kopie hinter das Original mit neuen Kennungen")
    func pageEdits() throws {
        let first = DashboardPage(name: "A", symbol: "star", template: .overview, widgets: [clock(f(0, 0, 110, 130))])
        #expect(DashboardPages(pages: []) == nil)
        var pages = try #require(DashboardPages(pages: [first]))
        #expect(!pages.removePage(id: first.id))
        let added = pages.addPage(name: "B")
        #expect(pages.pages.map(\.name) == ["A", "B"])
        let copyID = try #require(pages.duplicatePage(id: first.id, name: "A Kopie"))
        #expect(pages.pages.map(\.name) == ["A", "A Kopie", "B"])
        let copy = try #require(pages.page(id: copyID))
        #expect(copy.template == nil)
        #expect(copy.widgets.count == 1)
        #expect(copy.widgets[0].id != first.widgets[0].id)
        pages.renamePage(id: added, to: "Neu")
        pages.setSymbol("bolt", forPage: added)
        pages.movePages(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(pages.pages.map(\.name) == ["Neu", "A", "A Kopie"])
        #expect(pages.pages[0].symbol == "bolt")
        #expect(pages.removePage(id: added))
    }

    @Test("Wiederherstellen haengt nur fehlende Vorlagen an")
    func restore() throws {
        let overview = DashboardPage(name: "Mein Dashboard", symbol: "star", template: .overview)
        var pages = try #require(DashboardPages(pages: [overview]))
        let defaults = PageTemplate.allCases.map { DashboardPage(name: $0.rawValue, symbol: "x", template: $0) }
        pages.restoreDefaults(from: defaults)
        #expect(pages.pages.map(\.name) == ["Mein Dashboard", "media", "performance", "weather"])
    }

    @Test("Knopf fuer eine Seite: Vorlage, sonst erstes passendes Widget, sonst erste Seite")
    func resolve() throws {
        let own = DashboardPage(name: "Eigene", symbol: "star")
        var withMedia = DashboardPage(name: "Musik", symbol: "star")
        #expect(withMedia.add(WidgetInstance(kind: .media, frame: f(0, 0, 300, 130))))
        let mediaPage = DashboardPage(name: "Medien", symbol: "x", template: .media)
        let all = try #require(DashboardPages(pages: [own, withMedia, mediaPage]))
        #expect(all.page(for: .media, showing: [.media, .mediaPlayer]).name == "Medien")
        let noTemplate = try #require(DashboardPages(pages: [own, withMedia]))
        #expect(noTemplate.page(for: .media, showing: [.media, .mediaPlayer]).name == "Musik")
        #expect(noTemplate.page(for: .weather, showing: [.weatherHero]).name == "Eigene")
        #expect(noTemplate.usesMedia)
        #expect(!noTemplate.usesWeather)
    }

    @Test("Lesen: kaputte Seiten und Widgets fallen weg, leere Liste ist nicht lesbar")
    func decoding() throws {
        let json = #"""
        [{"id":"00000000-0000-0000-0000-00000000000A","name":"A","template":"overview",
          "widgets":[{"kind":"clock","frame":{"x":0,"y":0,"width":110,"height":130}},{"kind":"toaster"}]},
         5,
         {"name":"B","template":"nope"}]
        """#
        let pages = try JSONDecoder().decode(DashboardPages.self, from: Data(json.utf8))
        #expect(pages.pages.map(\.name) == ["A", "B"])
        #expect(pages.pages[0].widgets.map(\.kind) == [.clock])
        #expect(pages.pages[1].template == nil)
        #expect(pages.pages[1].symbol == DashboardPage.defaultSymbol)
        #expect((try? JSONDecoder().decode(DashboardPages.self, from: Data("[]".utf8))) == nil)
        let data = try JSONEncoder().encode(pages)
        #expect(try JSONDecoder().decode(DashboardPages.self, from: data) == pages)
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `./test.sh --filter DashboardPagesTests`
Expected: compile error, `DashboardPage` unknown.

- [ ] **Step 3: Implement `DashboardPages.swift`**

```swift
import Foundation

/// Vorlage einer mitgelieferten Seite - die vier Reiter von vor 0.2. Ueber
/// die Vorlage finden "Standardseiten wiederherstellen" und die Knoepfe,
/// die eine bestimmte Seite oeffnen (Medien in der Leiste), ihre Seite.
/// Rohwert steht in settings.json - nie umbenennen.
public enum PageTemplate: String, Codable, CaseIterable, Sendable {
    case overview, media, performance, weather

    public init(_ tab: DashboardTab) {
        self = switch tab {
        case .dashboard: .overview
        case .media: .media
        case .performance: .performance
        case .weather: .weather
        }
    }

    public var tab: DashboardTab {
        switch self {
        case .overview: .dashboard
        case .media: .media
        case .performance: .performance
        case .weather: .weather
        }
    }
}

/// Eine Seite des Dashboards: Name, Symbol, Widgets an freien Plaetzen.
/// Immer gueltig: jedes Widget liegt auf der Seite, hat eine erlaubte
/// Groesse und haelt `BentoGeometry.spacing` Abstand zu den anderen.
public struct DashboardPage: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    /// Mitgelieferte Seite (`nil` fuer eigene und Kopien).
    public var template: PageTemplate?
    public private(set) var widgets: [WidgetInstance]

    public static let defaultSymbol = "square.grid.2x2"

    public init(id: UUID = UUID(), name: String, symbol: String, template: PageTemplate? = nil,
                widgets: [WidgetInstance] = []) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.template = template
        self.widgets = Self.normalized(widgets)
    }

    /// Nur gueltige Widgets, in ihrer Reihenfolge; bei zu nahen gewinnt das
    /// fruehere, bei doppelter Kennung ebenso.
    static func normalized(_ widgets: [WidgetInstance]) -> [WidgetInstance] {
        var kept: [WidgetInstance] = []
        for widget in widgets where !kept.contains(where: { $0.id == widget.id })
            && BentoGeometry.isValid(widget.frame, kind: widget.kind, others: kept.map(\.frame)) {
            kept.append(widget)
        }
        return kept
    }

    // MARK: Widgets

    public func frames(excluding id: WidgetInstance.ID? = nil) -> [WidgetFrame] {
        widgets.filter { $0.id != id }.map(\.frame)
    }

    public func contains(_ kind: WidgetKind) -> Bool { widgets.contains { $0.kind == kind } }

    /// Fuegt hinzu, wenn der Rahmen gueltig ist. `false`: nichts geaendert.
    @discardableResult
    public mutating func add(_ widget: WidgetInstance) -> Bool {
        guard !widgets.contains(where: { $0.id == widget.id }),
              BentoGeometry.isValid(widget.frame, kind: widget.kind, others: frames()) else { return false }
        widgets.append(widget)
        return true
    }

    /// Neuer Rahmen (Ziehen, Groesse). Ungueltig: `false`, der alte bleibt.
    @discardableResult
    public mutating func setFrame(_ frame: WidgetFrame, for id: WidgetInstance.ID) -> Bool {
        guard let index = widgets.firstIndex(where: { $0.id == id }),
              BentoGeometry.isValid(frame, kind: widgets[index].kind, others: frames(excluding: id))
        else { return false }
        widgets[index].frame = frame
        return true
    }

    public mutating func setOptions(_ options: WidgetOptions, for id: WidgetInstance.ID) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[index].options = options
    }

    public mutating func removeWidget(id: WidgetInstance.ID) {
        widgets.removeAll { $0.id == id }
    }

    /// Kopie mit neuen Kennungen fuer Seite und Widgets, ohne Vorlage - sonst
    /// gaebe es zwei Seiten fuer dieselbe Vorlage.
    public func duplicated(name: String) -> DashboardPage {
        DashboardPage(name: name, symbol: symbol,
                      widgets: widgets.map { WidgetInstance(kind: $0.kind, frame: $0.frame, options: $0.options) })
    }

    // MARK: Datei

    private enum CodingKeys: String, CodingKey { case id, name, symbol, template, widgets }

    /// Nachsichtig: fehlende Kennung wird neu, unbekannte Vorlage `nil`,
    /// unlesbare oder ungueltige Widgets fallen weg.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list: LenientList<WidgetInstance>? = c.lenient(.widgets)
        self.init(id: c.lenient(.id) ?? UUID(),
                  name: c.lenient(.name) ?? "",
                  symbol: c.lenient(.symbol) ?? Self.defaultSymbol,
                  template: c.lenient(.template),
                  widgets: list?.values ?? [])
    }
}

/// Alle Seiten in ihrer Reihenfolge. Nie leer: die letzte Seite laesst sich
/// nicht loeschen, und eine Datei ohne lesbare Seite gilt als nicht lesbar
/// (die App baut die Seiten dann neu, siehe `DashboardPages.migrated`).
///
/// In der Datei: `[{"id": ..., "name": ..., "symbol": ..., "template": ..., "widgets": [...]}, ...]`.
public struct DashboardPages: Codable, Equatable, Sendable {
    public private(set) var pages: [DashboardPage]

    /// `nil` fuer eine leere Liste. Doppelte Kennungen: die spaetere faellt weg.
    public init?(pages: [DashboardPage]) {
        var seen = Set<UUID>()
        let unique = pages.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { return nil }
        self.pages = unique
    }

    public init(from decoder: any Decoder) throws {
        let list = try LenientList<DashboardPage>(from: decoder)
        guard let value = DashboardPages(pages: list.values) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "keine Seite"))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(pages)
    }

    // MARK: Lesen

    public func page(id: DashboardPage.ID) -> DashboardPage? { pages.first { $0.id == id } }

    /// Fuer Knoepfe, die frueher einen Reiter oeffneten (Medien, Leistung,
    /// Wetter in der Leiste): die Seite mit der Vorlage, sonst die erste mit
    /// einem Widget aus `kinds`, sonst die erste ueberhaupt.
    public func page(for template: PageTemplate, showing kinds: [WidgetKind]) -> DashboardPage {
        pages.first { $0.template == template }
            ?? pages.first { page in kinds.contains(where: page.contains) }
            ?? pages[0]
    }

    /// Wetter abrufen kostet eine Anfrage, die Wiedergabe einen perl-Prozess:
    /// nur, wenn eine Seite ein solches Widget hat.
    public var usesWeather: Bool { pages.contains { $0.widgets.contains { $0.kind.usesPlaces } } }
    public var usesMedia: Bool { pages.contains { $0.widgets.contains { $0.kind.usesMedia } } }

    // MARK: Aendern

    /// Ersetzt die Seite mit derselben Kennung (Bearbeiten).
    public mutating func update(_ page: DashboardPage) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }) else { return }
        pages[index] = page
    }

    /// Leere Seite ans Ende.
    @discardableResult
    public mutating func addPage(name: String, symbol: String = DashboardPage.defaultSymbol) -> DashboardPage.ID {
        let page = DashboardPage(name: name, symbol: symbol)
        pages.append(page)
        return page.id
    }

    /// Kopie direkt hinter das Original. `nil`: kein solches Original.
    @discardableResult
    public mutating func duplicatePage(id: DashboardPage.ID, name: String) -> DashboardPage.ID? {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return nil }
        let copy = pages[index].duplicated(name: name)
        pages.insert(copy, at: index + 1)
        return copy.id
    }

    /// `false` fuer die letzte Seite oder eine unbekannte Kennung.
    @discardableResult
    public mutating func removePage(id: DashboardPage.ID) -> Bool {
        guard pages.count > 1, let index = pages.firstIndex(where: { $0.id == id }) else { return false }
        pages.remove(at: index)
        return true
    }

    public mutating func renamePage(id: DashboardPage.ID, to name: String) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].name = name
    }

    public mutating func setSymbol(_ symbol: String, forPage id: DashboardPage.ID) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].symbol = symbol
    }

    /// Wie SwiftUIs `onMove` (Ziel vor dem Verschieben gezaehlt).
    public mutating func movePages(fromOffsets source: IndexSet, toOffset destination: Int) {
        pages.move(fromOffsets: source, toOffset: destination)
    }

    /// Haengt die mitgelieferten Seiten an, deren Vorlage fehlt. Vorhandene
    /// Seiten bleiben, wie sie sind. `defaults`: `DashboardPages.defaultPages(...)`.
    public mutating func restoreDefaults(from defaults: [DashboardPage]) {
        let present = Set(pages.compactMap(\.template))
        pages += defaults.filter { page in page.template.map { !present.contains($0) } ?? false }
    }
}
```

- [ ] **Step 4: Run to see it pass**

Run: `./test.sh --filter DashboardPagesTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ApolloShellCore/DashboardPages.swift Tests/ApolloShellCoreTests/DashboardPagesTests.swift
git commit -m "Add dashboard pages with lenient reading and page management"
```

---

### Task 7: Preset pages and migration from 0.1.x

**Files:**
- Create: `Sources/ApolloShellCore/DashboardPagesDefaults.swift`
- Test: `Tests/ApolloShellCoreTests/DashboardMigrationTests.swift`

**Interfaces:**
- Consumes: Tasks 2, 3, 6; `DashboardLayout`, `DashboardCards`, `DashboardGeometry.placements(for:)`, `DashboardPreset`, `DashboardTab.title/symbol`.
- Produces: `PageTemplate.defaultPage(places: WeatherFavorites, hasBattery: Bool) -> DashboardPage`; `DashboardPages.defaultPages(places:hasBattery:) -> [DashboardPage]`; `DashboardPages.migrated(from: DashboardLayout, places: WeatherFavorites, hasBattery: Bool) -> DashboardPages`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Umzug von 0.1.x und mitgelieferte Seiten")
struct DashboardMigrationTests {
    private let chur = WeatherLocation(name: "Chur", latitude: 46.85, longitude: 9.53)
    private var places: WeatherFavorites { WeatherFavorites(locations: [chur], selectedID: chur.id) }

    private func frames(_ page: DashboardPage) -> [String] {
        page.widgets.map { "\($0.kind.rawValue) \(Int($0.frame.x)),\(Int($0.frame.y)) \(Int($0.frame.width))x\(Int($0.frame.height))" }
    }

    @Test("Uebersicht: jede Vorlage von vor 0.2 landet punktgenau", arguments: DashboardPreset.allCases)
    func overviewExact(preset: DashboardPreset) {
        let layout = preset.layout
        let pages = DashboardPages.migrated(from: layout, places: places, hasBattery: true)
        let overview = pages.pages.first { $0.template == .overview }
        let expected = DashboardGeometry.placements(for: layout.cards).map {
            "\($0.card.kind.rawValue) \(Int($0.frame.x)),\(Int($0.frame.y)) \(Int($0.frame.width))x\(Int($0.frame.height))"
        }
        #expect(overview.map(frames) == expected)
    }

    @Test("Caelestia-Uebersicht, Zahl fuer Zahl")
    func caelestiaNumbers() {
        let page = PageTemplate.overview.defaultPage(places: places, hasBattery: true)
        #expect(frames(page) == [
            "weather 0,0 275x130", "user 287,0 340x130",
            "clock 0,142 110x250", "calendar 122,142 403x250", "resources 537,142 90x250",
            "media 639,0 200x392",
        ])
    }

    @Test("Reihenfolge und Sichtbarkeit der Reiter, Optionen der Karten, Orte")
    func tabsAndOptions() {
        var cards = DashboardCards.caelestia
        cards.update(.clock(DashboardClockOptions(style: .inline, showDate: true)))
        let layout = DashboardLayout(tabs: DashboardTabs(order: [.weather, .dashboard, .media, .performance], hidden: [.media]),
                                     cards: cards)
        let pages = DashboardPages.migrated(from: layout, places: places, hasBattery: true)
        #expect(pages.pages.map(\.template) == [.weather, .overview, .performance])
        #expect(pages.pages.map(\.name) == [DashboardTab.weather.title, DashboardTab.dashboard.title, DashboardTab.performance.title])
        let clock = pages.pages[1].widgets.first { $0.kind == .clock }
        #expect(clock?.options.clock == DashboardClockOptions(style: .inline, showDate: true))
        #expect(pages.pages[1].widgets.first { $0.kind == .weather }?.options.places == places)
        #expect(pages.pages[0].widgets.allSatisfy { $0.options.places == places })
    }

    @Test("Seite Leistung mit und ohne Akku")
    func performance() {
        #expect(frames(PageTemplate.performance.defaultPage(places: .empty, hasBattery: true)) == [
            "performance.cpu 0,0 343x191", "performance.gpu 355,0 343x191",
            "performance.storage 0,203 169x189", "performance.network 181,203 335x189",
            "performance.memory 528,203 170x189", "performance.battery 710,0 129x392",
        ])
        #expect(frames(PageTemplate.performance.defaultPage(places: .empty, hasBattery: false)) == [
            "performance.cpu 0,0 413x191", "performance.gpu 425,0 414x191",
            "performance.storage 0,203 240x189", "performance.network 252,203 335x189",
            "performance.memory 599,203 240x189",
        ])
    }

    @Test("Seiten Wetter und Medien")
    func weatherAndMedia() {
        #expect(frames(PageTemplate.weather.defaultPage(places: places, hasBattery: true)) == [
            "weather.hero 0,0 839x116", "weather.hourly 0,128 839x108", "weather.daily 0,248 839x144",
        ])
        #expect(frames(PageTemplate.media.defaultPage(places: places, hasBattery: true)) == ["media.player 0,0 839x392"])
    }

    @Test("Vorgaben: vier Seiten in der Reihenfolge von vor 0.2, mit Namen und Symbolen der Reiter")
    func defaults() {
        let pages = DashboardPages.defaultPages(places: places, hasBattery: true)
        #expect(pages.map(\.template) == [.overview, .media, .performance, .weather])
        #expect(pages.map(\.symbol) == DashboardTab.allCases.map(\.symbol))
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `./test.sh --filter DashboardMigrationTests`
Expected: compile error, `migrated` unknown.

- [ ] **Step 3: Implement `DashboardPagesDefaults.swift`**

```swift
import Foundation

// Die mitgelieferten Seiten (die vier Reiter von vor 0.2, punktgenau) und
// der einmalige Umzug der Einstellungen von 0.1.x.

public extension PageTemplate {
    /// Die mitgelieferte Seite in der Form von vor 0.2. `places`: Orte der
    /// Wetter-Widgets (beim Umzug die Favoriten aus weather.json);
    /// `hasBattery`: Seite Leistung mit Akku rechts oder ohne.
    func defaultPage(places: WeatherFavorites, hasBattery: Bool) -> DashboardPage {
        DashboardPage(name: tab.title, symbol: tab.symbol, template: self,
                      widgets: defaultWidgets(places: places, hasBattery: hasBattery))
    }

    internal func defaultWidgets(places: WeatherFavorites, hasBattery: Bool) -> [WidgetInstance] {
        let width = DashboardGeometry.width
        let spacing = DashboardGeometry.spacing
        switch self {
        case .overview:
            return DashboardPages.overviewWidgets(.caelestia, places: places)
        case .media:
            return [WidgetInstance(kind: .mediaPlayer, frame: WidgetFrame(x: 0, y: 0, width: width, height: DashboardGeometry.height))]
        case .weather:
            let g = WeatherPageGeometry.self
            func widget(_ kind: WidgetKind, y: Double, height: Double) -> WidgetInstance {
                WidgetInstance(kind: kind, frame: WidgetFrame(x: 0, y: y, width: width, height: height),
                               options: .defaults(for: kind, places: places))
            }
            return [
                widget(.weatherHero, y: 0, height: g.heroHeight),
                widget(.weatherHourly, y: g.heroHeight + g.spacing, height: g.hourlyHeight),
                widget(.weatherDaily, y: g.heroHeight + g.hourlyHeight + 2 * g.spacing, height: g.dailyHeight),
            ]
        case .performance:
            let p = PerformancePageGeometry.self
            let hero = p.heroWidths(hasBattery: hasBattery)
            let side = p.sideWidths(hasBattery: hasBattery)
            let bottomY = p.heroHeight + spacing
            var result = [
                WidgetInstance(kind: .performanceCPU, frame: WidgetFrame(x: 0, y: 0, width: hero[0], height: p.heroHeight)),
                WidgetInstance(kind: .performanceGPU, frame: WidgetFrame(x: hero[0] + spacing, y: 0, width: hero[1], height: p.heroHeight)),
                WidgetInstance(kind: .performanceStorage, frame: WidgetFrame(x: 0, y: bottomY, width: side[0], height: p.bottomHeight)),
                WidgetInstance(kind: .performanceNetwork, frame: WidgetFrame(x: side[0] + spacing, y: bottomY,
                                                                             width: p.networkWidth, height: p.bottomHeight)),
                WidgetInstance(kind: .performanceMemory, frame: WidgetFrame(x: side[0] + spacing + p.networkWidth + spacing,
                                                                            y: bottomY, width: side[1], height: p.bottomHeight)),
            ]
            if hasBattery {
                result.append(WidgetInstance(kind: .performanceBattery,
                                             frame: WidgetFrame(x: p.leftWidth(hasBattery: true) + spacing, y: 0,
                                                                width: p.batteryWidth, height: DashboardGeometry.height)))
            }
            return result
        }
    }
}

public extension DashboardPages {
    /// Die vier mitgelieferten Seiten in der Reihenfolge der Reiter von vor 0.2.
    static func defaultPages(places: WeatherFavorites, hasBattery: Bool) -> [DashboardPage] {
        PageTemplate.allCases.map { $0.defaultPage(places: places, hasBattery: hasBattery) }
    }

    /// Umzug beim ersten Start von 0.2: die sichtbaren Reiter in ihrer
    /// Reihenfolge, die Uebersicht mit genau ihren Karten und Optionen an
    /// genau ihren Plaetzen. Ausgeblendete Reiter kommen nicht mit
    /// ("Standardseiten wiederherstellen" holt sie zurueck).
    static func migrated(from layout: DashboardLayout, places: WeatherFavorites, hasBattery: Bool) -> DashboardPages {
        let pages = layout.tabs.visible.map { tab -> DashboardPage in
            let template = PageTemplate(tab)
            guard template == .overview else { return template.defaultPage(places: places, hasBattery: hasBattery) }
            return DashboardPage(name: tab.title, symbol: tab.symbol, template: .overview,
                                 widgets: overviewWidgets(layout.cards, places: places))
        }
        // `visible` ist nie leer (DashboardTabs); zur Sicherheit trotzdem die Vorgaben.
        return DashboardPages(pages: pages) ?? DashboardPages(pages: defaultPages(places: places, hasBattery: hasBattery))!
    }

    /// Karten der Uebersicht als Widgets, an den Rahmen von
    /// `DashboardGeometry.placements` und mit ihren Optionen.
    internal static func overviewWidgets(_ cards: DashboardCards, places: WeatherFavorites) -> [WidgetInstance] {
        DashboardGeometry.placements(for: cards).map { placement in
            let kind = WidgetKind(placement.card.kind)
            var options = WidgetOptions.defaults(for: kind, places: places)
            switch placement.card {
            case .weather(let o): options.weather = o
            case .user(let o): options.user = o
            case .clock(let o): options.clock = o
            case .calendar(let o): options.calendar = o
            case .resources(let o): options.resources = o
            case .media(let o): options.media = o
            }
            return WidgetInstance(kind: kind, frame: WidgetFrame(placement.frame), options: options)
        }
    }
}
```

- [ ] **Step 4: Run to see it pass**

Run: `./test.sh --filter DashboardMigrationTests`
Expected: PASS. If `overviewExact` loses a widget, `DashboardPage.normalized` dropped it: print the frame and check it against `WidgetKind.sizes` and `BentoGeometry.tooClose` — the old geometry is the reference, the new rules must accept it.

- [ ] **Step 5: Commit**

```bash
git add Sources/ApolloShellCore/DashboardPagesDefaults.swift Tests/ApolloShellCoreTests/DashboardMigrationTests.swift
git commit -m "Build the preset pages and migrate the 0.1 dashboard to pages"
```

---

### Task 8: Settings fields

**Files:**
- Modify: `Sources/ApolloShellCore/ShellSettings.swift` (properties near line 26, `init(...)` near line 45, `init(from:)` near line 246)
- Test: `Tests/ApolloShellCoreTests/ShellSettingsTests.swift` (append)

**Interfaces:**
- Consumes: `DashboardPages`, `BentoGeometry.clampedUserScale`.
- Produces: `ShellSettings.dashboardPages: DashboardPages?`, `ShellSettings.dashboardScale: Double`.

- [ ] **Step 1: Write the failing test** — append inside the suite struct in `ShellSettingsTests.swift`:

```swift
    // MARK: Seiten des Dashboards (0.2)

    @Test("Seiten und Groesse: fehlen in alten Dateien, Regler begrenzt, alter Abschnitt bleibt")
    func dashboardPages() throws {
        let old = ShellSettings.load(from: Data(#"{"dashboard":{"tabs":[{"id":"media","visible":false}]}}"#.utf8))
        #expect(old.dashboardPages == nil)
        #expect(old.dashboardScale == 1)

        var settings = old
        settings.dashboardPages = DashboardPages(pages: DashboardPages.defaultPages(places: .empty, hasBattery: true))
        settings.dashboardScale = 1.2
        let reread = ShellSettings.load(from: settings.encoded())
        #expect(reread.dashboardPages == settings.dashboardPages)
        #expect(reread.dashboardScale == 1.2)
        #expect(reread.dashboard == old.dashboard)

        let loud = ShellSettings.load(from: Data(#"{"dashboardScale":9,"dashboardPages":[]}"#.utf8))
        #expect(loud.dashboardScale == 1.5)
        #expect(loud.dashboardPages == nil)
    }
```

- [ ] **Step 2: Run to see it fail**

Run: `./test.sh --filter ShellSettingsTests`
Expected: compile error, `dashboardPages` unknown.

- [ ] **Step 3: Implement**

Add after `public var dashboard = DashboardLayout()`:

```swift
    /// Seiten des Bento-Dashboards (0.2). `nil`: noch nie gespeichert oder
    /// nicht lesbar - die App baut sie dann einmal aus `dashboard`
    /// (`DashboardPages.migrated`). `dashboard` selbst bleibt unangetastet,
    /// damit ein Zurueck auf 0.1.x nichts verliert.
    public var dashboardPages: DashboardPages?
    /// Groesse des Dashboards zusaetzlich zur Automatik nach Bildschirm
    /// (Nexus-Regler), `BentoGeometry.userScaleRange`.
    public var dashboardScale: Double = 1
```

Add two parameters to `init(...)` right after `dashboard:` and assign them:

```swift
                dashboardPages: DashboardPages? = nil,
                dashboardScale: Double = 1,
```
```swift
        self.dashboardPages = dashboardPages
        self.dashboardScale = BentoGeometry.clampedUserScale(dashboardScale)
```

In `init(from:)` after the `dashboard = ...` line:

```swift
        dashboardPages = c.lenient(.dashboardPages)
        dashboardScale = BentoGeometry.clampedUserScale(c.lenient(.dashboardScale) ?? 1)
```

If `ShellSettings` declares its own top-level `CodingKeys`, add `dashboardPages` and `dashboardScale` there; if it relies on the synthesized ones, nothing else is needed (optional `nil` is omitted when writing). Check `firstLaunch` and any other place that calls the memberwise `init` still compiles.

- [ ] **Step 4: Run to see it pass**

Run: `./test.sh --filter ShellSettingsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ApolloShellCore/ShellSettings.swift Tests/ApolloShellCoreTests/ShellSettingsTests.swift
git commit -m "Store dashboard pages and the dashboard size in settings"
```

---

### Task 9: Full check

- [ ] **Step 1:** Run the whole suite once: `./test.sh`. Expected: all tests pass (about 760 old plus the new ones). Report the count.
- [ ] **Step 2:** Run `python3 scripts/check-l10n.py`. Expected: clean.
- [ ] **Step 3:** Build the app target without installing: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk swift build --product ApolloShell`. Expected: builds (nothing in the app uses the new types yet, but it must still compile).
- [ ] **Step 4:** Commit only if something had to be fixed.

---

## Later parts (separate plans, written after this part lands)

2. **Rendering** — pages from `DashboardPages` in the dashboard, page bar that scrolls, widget views per size from today's card views, scale factor, weather cache per place, sampler only with a performance widget, `usesWeather/usesMedia` from pages, migration call at startup (`hasBattery` from the status model, places from weather.json), offscreen render mode for checks. Watch out: the comment above `DashboardGrid` in `DashboardView.swift` records that absolutely placed frames shifted text by one pixel (x = 332.749…); pixel-round frames at the final scale or keep stacks where a preset is untouched, and compare renders.
3. **Edit mode** in the dashboard (wobble, `−`, handle, drag, drop from Nexus, selection, Done/Cancel).
4. **Nexus**: page list, widget list, options, slider; remove the old editor and the three templates.
5. **Docs, l10n, Opus review.**
