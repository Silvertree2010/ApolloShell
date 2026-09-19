import AppKit
import ApolloShellCore
import SwiftUI

/// Bildproben ohne laufende Shell: `ApolloShell --render-dashboard <Ordner>`
/// zeichnet das Dashboard mit festen Beispieldaten als PNG (2x, hell und
/// dunkel) und endet. Fasst weder Fenster, Kuerzel noch Dateien der Shell
/// an und laeuft deshalb auch neben einer laufenden ApolloShell. Zum
/// Pixelvergleich vor und nach Umbauten, siehe scripts/compare-renders.py.
@MainActor
enum RenderMode {
    /// Endet den Prozess, wenn ein Schalter gesetzt ist; sonst kehrt es zurueck.
    static func runIfRequested() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--render-dashboard"), index + 1 < args.count {
            run(folder: URL(fileURLWithPath: args[index + 1], isDirectory: true), renderDashboard)
        }
        if let index = args.firstIndex(of: "--render-edit"), index + 1 < args.count {
            run(folder: URL(fileURLWithPath: args[index + 1], isDirectory: true), renderEditMode)
        }
    }

    private static func run(folder: URL, _ body: (URL) throws -> Void) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try body(folder)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func renderDashboard(into folder: URL) throws {
        let fixtures = RenderFixtures()
        let place = WeatherLocation(name: "Berlin", latitude: 52.52, longitude: 13.405)
        let places = WeatherFavorites(locations: [place], selectedID: place.id)
        // Kein Akku: die Bildproben messen nie wirklich (`performance.battery`
        // bleibt `nil`), so zeigte auch das alte Dashboard keinen Tank.
        let pages = DashboardPages(pages: DashboardPages.defaultPages(places: places, hasBattery: false))!
        let settings = ShellSettingsStore.preview(ShellSettings(dashboardPages: pages))
        let weatherModels = WeatherModels.preview(fixtures.weather)
        let editor = DashboardEditor(store: settings)
        for page in pages.pages {
            fixtures.dashboard.pageID = page.id
            for scheme in [ColorScheme.light, .dark] {
                fixtures.dashboard.scale = 1
                let view = DashboardView(model: fixtures.dashboard, weatherModels: weatherModels,
                                         media: fixtures.media, settings: settings, editor: editor)
                try write(view, scheme: scheme, to: folder.appendingPathComponent(name(page.template!.tab.rawValue, scheme)))
            }
        }
        // Massstab 1,5, nur hell: fuer die eigene Pruefung, ob Text scharf
        // bleibt (kein Vergleich mit der Basisprobe - die kennt keinen
        // Massstab).
        let scaledFolder = folder.appendingPathComponent("scaled", isDirectory: true)
        try FileManager.default.createDirectory(at: scaledFolder, withIntermediateDirectories: true)
        for page in pages.pages {
            fixtures.dashboard.pageID = page.id
            fixtures.dashboard.scale = 1.5
            let view = DashboardView(model: fixtures.dashboard, weatherModels: weatherModels,
                                     media: fixtures.media, settings: settings, editor: editor)
            try write(view, scheme: .light, to: scaledFolder.appendingPathComponent(name(page.template!.tab.rawValue, .light)))
        }
        try renderEdit(into: folder, fixtures: fixtures, settings: settings, weatherModels: weatherModels, pages: pages)
    }

    /// `--render-dashboard`s `edit/`-Unterordner: die Uebersichtsseite in
    /// Bearbeitung, ein gewaehltes Widget, eine ungueltige Ablege-Vorschau,
    /// und dieselbe Ansicht mit `accessibilityReduceMotion`.
    private static func renderEdit(into folder: URL, fixtures: RenderFixtures, settings: ShellSettingsStore,
                                    weatherModels: WeatherModels, pages: DashboardPages) throws {
        let editFolder = folder.appendingPathComponent("edit", isDirectory: true)
        try FileManager.default.createDirectory(at: editFolder, withIntermediateDirectories: true)
        let overview = pages.pages[0]
        let editor = DashboardEditor(store: settings)
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            editor.begin(pageID: overview.id, screen: screen)
        }
        fixtures.dashboard.pageID = overview.id

        func view(reduceMotion: Bool) -> some View {
            DashboardView(model: fixtures.dashboard, weatherModels: weatherModels, media: fixtures.media,
                          settings: settings, editor: editor)
                .environment(\.dashboardReducesMotionOverride, reduceMotion)
                // Das Ablegeziel (`.onDrop`) zeichnet `ImageRenderer` offscreen
                // nicht (siehe `BentoDropTarget`) - fuer die Bildprobe weg.
                .environment(\.dashboardRendersForScreenshot, true)
        }
        try write(view(reduceMotion: false), scheme: .light, to: editFolder.appendingPathComponent("overview-light.png"))
        editor.selectedWidgetID = editor.page?.widgets.first?.id
        try write(view(reduceMotion: false), scheme: .light, to: editFolder.appendingPathComponent("selected-widget-light.png"))
        // Eine ungueltige Ablege-Vorschau (zu nah an einem Widget), so als
        // zoege man gerade ein zweites "Uhr"-Widget ueber die erste Karte.
        editor.dropPreview = editor.previewDrop(.clock, x: 60, y: 60).map { (frame: $0.frame, valid: $0.valid) }
        try write(view(reduceMotion: false), scheme: .light, to: editFolder.appendingPathComponent("invalid-drop-light.png"))
        editor.dropPreview = nil
        try write(view(reduceMotion: true), scheme: .light, to: editFolder.appendingPathComponent("reduce-motion-light.png"))
        // Kein Bild fuer den Options-Popover selbst: `.popover` ist ein
        // eigenes AppKit-Fenster, `ImageRenderer` zeichnet dessen Inhalt
        // offscreen nicht (ein `Form` mit `WidgetOptionsView` direkt blieb in
        // der Probe leer, vermutlich derselbe Grund wie bei `.onDrag`/
        // `.onDrop`). Die Auswahl selbst (blauer Rahmen) zeigt
        // `selected-widget-light.png`; die Regler in `WidgetOptionsView`
        // (`NexusWidgetOptions.swift`) sind dieselben wie vor 0.2 im
        // Nexus-Editor, dort schon im Bild geprueft.
    }

    /// `--render-edit <Ordner>`: die Werkzeugleiste und beide Reiter der
    /// Galerie des globalen Bearbeitungsmodus (Task 3), in `<Ordner>/edit/`.
    /// Reine SwiftUI-Ansichten (kein `NSGlassEffectView`-Panel noetig), damit
    /// `ImageRenderer` sie offscreen zeichnen kann.
    private static func renderEditMode(into folder: URL) throws {
        let editFolder = folder.appendingPathComponent("edit", isDirectory: true)
        try FileManager.default.createDirectory(at: editFolder, withIntermediateDirectories: true)
        let place = WeatherLocation(name: "Berlin", latitude: 52.52, longitude: 13.405)
        let places = WeatherFavorites(locations: [place], selectedID: place.id)
        let pages = DashboardPages(pages: DashboardPages.defaultPages(places: places, hasBattery: false))!
        let settings = ShellSettingsStore.preview(ShellSettings(dashboardPages: pages))
        let dashboardEditor = DashboardEditor(store: settings)
        let editor = ShellEditor(store: settings, dashboard: dashboardEditor)
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            editor.begin(screen: screen)
        }
        try write(EditToolbarView(editor: editor), scheme: .light, to: editFolder.appendingPathComponent("toolbar-light.png"))
        // Esc mit Aenderungen (Task 6): die Werkzeugleiste fragt nach, statt
        // sofort abzubrechen.
        editor.dashboard.addPage()
        editor.pendingCancelConfirmation = true
        try write(EditToolbarView(editor: editor), scheme: .light, to: editFolder.appendingPathComponent("toolbar-confirm-light.png"))
        editor.pendingCancelConfirmation = false
        editor.galleryTab = .dashboard
        try write(EditGalleryView(editor: editor).environment(\.galleryRendersForScreenshot, true), scheme: .light,
                 to: editFolder.appendingPathComponent("gallery-dashboard-light.png"))
        editor.galleryTab = .controlCentre
        try write(EditGalleryView(editor: editor).environment(\.galleryRendersForScreenshot, true), scheme: .light,
                 to: editFolder.appendingPathComponent("gallery-controlcentre-light.png"))
        // Kontrollzentrum in der Bearbeitung (Task 5): ein Knopf gewaehlt -
        // wackeln selbst zeichnet `ImageRenderer` nicht (feste Momentaufnahme
        // mitten in der Dauerschleife), aber Rahmen, Minus-Abzeichen und
        // Ziel-Hervorhebung sind ohne Bewegung zu sehen. Lautstaerke-Regler
        // und Geraete-Knoepfe der Ton-Karte (`UtilitiesAudioCard`) sind
        // selbst AppKit-hinterlegt (eigene Ziehflaeche, `NSMenu`) - dieselbe
        // Ursache wie bei `.onDrag`/`.onDrop`: offscreen zeichnet
        // `ImageRenderer` sie als rotes Verbotszeichen statt ihrer echten
        // Form. Im echten Fenster (nicht offscreen) sehen sie normal aus,
        // nur ohne Wirkung (`allowsHitTesting(false)`).
        if let toggleID = editor.utilities?.layout.toggles.first?.id {
            editor.selectedToggleID = toggleID
        }
        let utilitiesView = EditableUtilitiesView(editor: editor, layout: editor.utilities?.layout ?? UtilitiesLayout())
            .environment(\.dashboardRendersForScreenshot, true)
        try write(utilitiesView, scheme: .light, to: editFolder.appendingPathComponent("utilities-selected-light.png"))
    }

    static func name(_ base: String, _ scheme: ColorScheme) -> String {
        "\(base)-\(scheme == .dark ? "dark" : "light").png"
    }

    /// Ohne Theme-Speicher (`shellTheme(nil)`): immer die Vorgaben, egal
    /// welches Theme der Nutzer gewaehlt hat. Deckender Hintergrund, weil
    /// Glas offscreen nicht gezeichnet wird.
    static func write(_ view: some View, scheme: ColorScheme, to url: URL) throws {
        let content = view
            .shellTheme(nil)
            .environment(\.colorScheme, scheme)
            .background(scheme == .dark ? Color.black : Color.white)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw RenderError.noImage(url.lastPathComponent) }
        try data.write(to: url)
    }

    enum RenderError: Error { case noImage(String) }
}

/// Feste Beispieldaten fuer Bildproben: fester Zeitpunkt, feste Werte,
/// nichts misst und nichts ruft ins Netz.
@MainActor
final class RenderFixtures {
    /// Freitag, 18.09.2026, 14:05 in der Zeitzone des Rechners.
    let now: Date = {
        var components = DateComponents(year: 2026, month: 9, day: 18, hour: 14, minute: 5)
        components.calendar = Calendar(identifier: .gregorian)
        return components.date!
    }()

    lazy var dashboard = DashboardModel.preview(now: now, cpu: 0.23, memory: 0.58, storage: 0.46,
                                                userName: "Alex Beispiel", uptime: 11_520)

    lazy var weather: WeatherModel = {
        let calendar = Calendar(identifier: .gregorian)
        let hours = (0..<24).map { offset in
            HourForecast(time: calendar.date(byAdding: .hour, value: offset, to: now)!,
                         temperature: 18 - Double(offset % 8), code: [0, 1, 2, 3, 61][offset % 5],
                         precipitationProbability: (offset * 7) % 60, isDay: (6..<20).contains((14 + offset) % 24))
        }
        let days = (0..<7).map { offset in
            DayForecast(date: calendar.date(byAdding: .day, value: offset, to: now)!, code: [2, 0, 3, 61, 1, 2, 0][offset],
                        maxTemperature: 21 - Double(offset), minTemperature: 11 - Double(offset % 3),
                        sunrise: nil, sunset: nil, precipitationProbability: (offset * 13) % 80)
        }
        let report = WeatherReport(
            current: CurrentWeather(time: now, temperature: 18, apparentTemperature: 17, humidity: 60,
                                    code: 2, windSpeed: 8, isDay: true),
            hours: hours, days: days, timeZone: .current
        )
        return WeatherModel.preview(report: report, fetchedAt: now, now: now)
    }()

    lazy var media: MediaModel = {
        let playing = MediaNowPlaying(title: "Sample Title", artist: "Sample Artist", album: "Sample Album",
                                      isPlaying: false, duration: 240, elapsed: 80, timestamp: now, playbackRate: 0)
        return MediaModel.preview(nowPlaying: playing, source: MediaSource(name: "Musik", icon: nil), now: now)
    }()
}
