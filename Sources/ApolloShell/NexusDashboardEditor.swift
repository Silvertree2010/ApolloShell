import AppKit
import ApolloShellCore
import SwiftUI

// Nexus > Dashboard: die verkleinerte Vorschau der gewaehlten Seite (nicht
// editierend, unten in NexusDashboardPage.swift). Der Baukasten (Seiten,
// Widgets, Optionen) steht seit 0.2 in NexusDashboardPages.swift,
// NexusDashboardWidgets.swift und NexusWidgetOptions.swift - die alten,
// kartenbasierten Bausteine (Reiter, Karten, Galerie, Vorlagen-Rueckfrage)
// sind mit den drei Vorlagen selbst weg (design/2026-09-18-bento-plan-
// edit.md Task 4).

/// Das echte Dashboard mit Vorschau-Modellen, verkleinert, bei der
/// gewaehlten Seite (`pageID`, `nil` = die erste). Unten fest statt rechts
/// wie bei der Leiste: das Dashboard ist breit, nicht hoch - daneben waere
/// es winzig. Ohne Maus: ein Klick hier soll nichts ausloesen.
struct NexusDashboardPreview: View {
    let store: ShellSettingsStore
    var pageID: DashboardPage.ID?

    /// Hoehe des Streifens: ein gutes Drittel der Seite, in Grenzen.
    static func height(for page: CGFloat) -> CGFloat {
        min(max(page * 0.36, 170), 300)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = NexusDashboardPreviewModels.size
            // Der Rahmen (`frameSize`) folgt dem ungeklemmten Massstab, der
            // sichtbare Inhalt (`scale`) bleibt bei mindestens 0.1 - sonst
            // waere er bei ganz kleinem Fenster unleserlich klein statt nur
            // beschnitten.
            let rawScale = min(1, (geometry.size.width - 40) / size.width, (geometry.size.height - 34) / size.height)
            let scale = max(rawScale, 0.1)
            VStack(spacing: 6) {
                NexusScaledPreview(scale: scale, frameSize: CGSize(width: size.width * rawScale, height: size.height * rawScale),
                                   cornerRadius: 25, accessibilityLabel: String(localized: "Vorschau des Dashboards")) {
                    DashboardView(model: NexusDashboardPreviewModels.dashboard,
                                  weatherModels: NexusDashboardPreviewModels.weatherModels,
                                  media: NexusDashboardPreviewModels.media, settings: store,
                                  editor: NexusDashboardPreviewModels.editor)
                }
                Text("Vorschau mit Beispieldaten")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { NexusDashboardPreviewModels.dashboard.pageID = pageID }
            .onChange(of: pageID) { _, id in NexusDashboardPreviewModels.dashboard.pageID = id }
        }
        .background(Color.primary.opacity(0.025))
    }
}

/// Feste Modelle fuer die Vorschau: messen, rufen und starten nichts. Die
/// Wiedergabe steht auf Pause, damit das Wellensymbol der Quelle nicht
/// dauernd zeichnet, solange Nexus offen ist.
@MainActor
enum NexusDashboardPreviewModels {
    static let now = Date()

    static let dashboard = DashboardModel.preview(now: now, cpu: 0.23, memory: 0.58, storage: 0.46,
                                                  userName: "Alex Beispiel", uptime: 11_520)

    static let weather: WeatherModel = {
        let today = DayForecast(date: now, code: 2, maxTemperature: 21, minTemperature: 11,
                                sunrise: nil, sunset: nil, precipitationProbability: 10)
        let report = WeatherReport(
            current: CurrentWeather(time: now, temperature: 18, apparentTemperature: 17, humidity: 60,
                                    code: 2, windSpeed: 8, isDay: true),
            hours: [], days: [today], timeZone: .current
        )
        return WeatherModel.preview(report: report, fetchedAt: now, now: now)
    }()

    static let weatherModels = WeatherModels.preview(weather)

    /// Bearbeitet nie: die Vorschau zeigt immer die ruhige Ansicht.
    static let editor = DashboardEditor(store: .preview())

    static let media: MediaModel = {
        let playing = MediaNowPlaying(title: String(localized: "Beispieltitel"), artist: String(localized: "Beispielband"),
                                      album: String(localized: "Beispielalbum"),
                                      isPlaying: false, duration: 240, elapsed: 80, timestamp: now, playbackRate: 0)
        let music = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music")
        let source = MediaSource(name: "Musik", icon: music.map { NSWorkspace.shared.icon(forFile: $0.path) })
        return MediaModel.preview(nowPlaying: playing, source: source, now: now)
    }()

    /// Das ganze Dashboard (Reiter und Raster), einmal gemessen - wie
    /// `Dashboard` es fuer sein Fenster tut. Haengt nicht an der Anordnung.
    static let size: CGSize = NSHostingView(rootView: DashboardView(
        model: dashboard, weatherModels: weatherModels, media: media, settings: .preview(), editor: editor
    ).shellTheme()).fittingSize
}
