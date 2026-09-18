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
    /// Endet den Prozess, wenn der Schalter gesetzt ist; sonst kehrt es zurueck.
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--render-dashboard"), index + 1 < args.count else { return }
        let folder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try renderDashboard(into: folder)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func renderDashboard(into folder: URL) throws {
        let fixtures = RenderFixtures()
        for tab in DashboardTab.allCases {
            fixtures.dashboard.tab = tab
            for scheme in [ColorScheme.light, .dark] {
                let view = DashboardView(model: fixtures.dashboard, weather: fixtures.weather,
                                         media: fixtures.media, settings: .preview())
                try write(view, scheme: scheme, to: folder.appendingPathComponent(name(tab.rawValue, scheme)))
            }
        }
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
        let playing = MediaNowPlaying(title: "Beispieltitel", artist: "Beispielband", album: "Beispielalbum",
                                      isPlaying: false, duration: 240, elapsed: 80, timestamp: now, playbackRate: 0)
        return MediaModel.preview(nowPlaying: playing, source: MediaSource(name: "Musik", icon: nil), now: now)
    }()
}
