import ApolloShellCore
import SwiftUI

// Wetter im Dashboard, nach Caelestia (modules/dashboard/dash/SmallWeather.qml
// und modules/dashboard/WeatherTab.qml) in Apple-Optik: SF Symbols in
// Mehrfarben statt Material-Icons, SF Rounded fuer die grossen Zahlen.
//
// Beide Ansichten laufen in einer TimelineView pro Minute: "Jetzt" in der
// Stundenleiste, "Heute" und "Stand" haengen an der Uhr, nicht nur an neuen
// Daten.

/// Karte im Dashboard-Raster (Caelestia: Slot 275 x 130, Radius 42): Symbol
/// links, daneben Temperatur und Wetterlage, als Gruppe mittig wie bei
/// Caelestia. Hochkant (untere Reihe, Seitenspalte) steht das Symbol ueber
/// den Zahlen - nebeneinander passte es in 200 Punkte Breite nicht.
///
/// Nicht `WeatherCard`: so heisst der Platzhalter in DashboardView.swift, und
/// gleichnamige Typen im Modul sind ein Fehler, auch wenn einer privat ist.
struct SmallWeatherCard: View {
    let model: WeatherModel
    /// Nexus > Dashboard; die Vorgabe zeigt alles wie Caelestia.
    var options = DashboardWeatherOptions()
    var vertical = false
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = model.fixedNow ?? context.date
            WeatherSurface(radius:42) {
                if vertical {
                    VStack(spacing: 8) {
                        content(now: now, alignment: .center)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                } else {
                    HStack(spacing: 16) {
                        content(now: now, alignment: .leading)
                    }
                    .padding(.horizontal, 26)
                }
            }
        }
        // Quelle auch hier, nur als Hinweis: die Karte ist zu klein fuer
        // eine eigene Zeile, der Reiter zeigt sie sichtbar.
        .help(helpText)
    }

    private var helpText: String {
        guard let location = model.location else { return "Ort in Nexus festlegen" }
        guard model.report != nil else { return "Wetter in \(location.name)" }
        return "Wetter in \(location.name) · \(model.attribution.text)"
    }

    /// Symbol und Zahlen; neben- oder untereinander bestimmt der Aufrufer.
    @ViewBuilder
    private func content(now: Date, alignment: HorizontalAlignment) -> some View {
        if let report = model.report {
            let current = report.current
            WeatherSymbol(name: WeatherCondition.symbol(code: current.code, isDay: current.isDay), size: 46)
            VStack(alignment: alignment, spacing: 1) {
                Text(WeatherText.temperature(current.temperature))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                if options.showCondition {
                    Text(WeatherCondition.description(code: current.code))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                }
                if options.showRange, let today = report.today(now: now) {
                    Text(WeatherText.range(max: today.maxTemperature, min: today.minTemperature))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let stand = model.standText(now: now) {
                    Text(stand).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)
        } else if model.location == nil {
            WeatherSymbol(name: "location.slash", size: 40, placeholder: true)
            VStack(alignment: alignment, spacing: 2) {
                Button("Ort in Nexus festlegen") { model.onOpenNexus() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(style.accent)
            }
        } else {
            WeatherSymbol(name: "cloud.sun", size: 40, placeholder: true)
            VStack(alignment: alignment, spacing: 2) {
                Text("--°").font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(model.lastAttemptFailed ? String(localized: "Keine Wetterdaten") : String(localized: "Wird geladen …"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Reiter "Wetter", fuellt die Inhaltsflaeche des Dashboards (839 x 392):
/// oben die aktuelle Lage mit den Details (Caelestia: Kopfzeile, grosse
/// Info-Zeile und DetailCards in einer Karte), darunter die Stundenleiste,
/// unten sieben Tage nebeneinander wie bei Caelestia.
struct WeatherTab: View {
    let model: WeatherModel

    private static let spacing: CGFloat = 12
    private static let heroHeight: CGFloat = 116
    private static let hourlyHeight: CGFloat = 108

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = model.fixedNow ?? context.date
            if let report = model.report {
                VStack(spacing: Self.spacing) {
                    WeatherHero(report: report, model: model, now: now,
                             stand: model.standText(now: now))
                        .frame(height: Self.heroHeight)
                    WeatherHourly(slots: report.hourlyStrip(now: now), calendar: report.calendar)
                        .frame(height: Self.hourlyHeight)
                    WeatherDaily(days: report.upcomingDays(now: now), now: now, calendar: report.calendar)
                }
            } else if model.location == nil {
                VStack(spacing: 10) {
                    Image(systemName: "location.slash").font(.system(size: 36, weight: .light)).foregroundStyle(.secondary)
                    Text("Ort in Nexus festlegen")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Ohne Favoriten gibt es kein Wetter zum Anzeigen.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Nexus öffnen") { model.onOpenNexus() }
                        .padding(.top, 2)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "cloud.sun").font(.system(size: 36, weight: .light)).foregroundStyle(.secondary)
                    Text(model.lastAttemptFailed ? String(localized: "Keine Wetterdaten") : String(localized: "Wetter wird geladen …"))
                        .font(.system(size: 15, weight: .semibold))
                    // Auch ohne Daten umschaltbar - vielleicht klappt es woanders.
                    WeatherPlacePicker(model: model)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Bausteine

/// Karte mit leicht abgesetzter Flaeche auf dem Glas, wie im Dashboard.
private struct WeatherSurface<Content: View>: View {
    let radius: CGFloat
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        // Dieselbe Flaeche wie `Card` im Dashboard, also auch mit Theme
        // dieselbe: sonst bleibt diese eine Karte hell zwischen lauter
        // eingefaerbten.
        let shape = RoundedRectangle(cornerRadius: style.cardRadius(radius))
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if style.isThemed {
                    shape.fill(style.cardFill)
                } else {
                    shape.fill(Color.primary.opacity(0.06))
                }
            }
    }
}

/// Wettersymbol in Mehrfarben (Sonne gelb, Regen blau). Der Platzhalter
/// bleibt grau, damit "noch nichts da" nicht wie Wetter aussieht.
private struct WeatherSymbol: View {
    let name: String
    let size: CGFloat
    var placeholder = false

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size))
            .symbolRenderingMode(placeholder ? .hierarchical : .multicolor)
            .foregroundStyle(placeholder ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .modifier(SymbolContour())
            .accessibilityHidden(true)
    }
}

/// Mehrfarbige Wettersymbole haben weisse Wolken, Schneeflocken und
/// Horizontlinien - auf der hellen Karte fast unsichtbar (Bildprobe 14.09.).
/// Im Hellen deshalb ein feiner Schatten als Kontur; im Dunkeln stehen sie
/// von selbst.
private struct SymbolContour: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(colorScheme == .light ? 0.3 : 0), radius: 0.8, y: 0.4)
    }
}

/// Regenwahrscheinlichkeit in Blau wie bei Apple Wetter; im Hellen dunkler,
/// sonst verschwindet Cyan auf der hellen Karte. Unter 20 % bleibt die
/// Zeile leer, behaelt aber ihre Hoehe, damit die Spalten buendig bleiben.
private struct WeatherPrecipitation: View {
    let percent: Int?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(WeatherText.precipitation(percent) ?? " ")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? Color.cyan : Color.blue)
            .frame(height: 12)
    }
}

// MARK: - Reiter

/// Ortswahl als Kapseln, aus den Favoriten (Nexus > Dashboard): der gewaehlte
/// in Akzentfarbe.
private struct WeatherPlacePicker: View {
    let model: WeatherModel
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(model.favorites.locations) { place in
                let selected = place == model.location
                Button {
                    model.select(place)
                } label: {
                    Text(place.name)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .foregroundStyle(selected ? AnyShapeStyle(style.onAccent) : AnyShapeStyle(.secondary))
                        .background(
                            selected ? AnyShapeStyle(style.accent) : AnyShapeStyle(Color.primary.opacity(0.08)),
                            in: .capsule
                        )
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .help("Wetter für \(place.name)")
            }
        }
        .fixedSize()
        .animation(.easeOut(duration: 0.15), value: model.location)
    }
}

private struct WeatherHero: View {
    let report: WeatherReport
    let model: WeatherModel
    let now: Date
    let stand: String?

    var body: some View {
        let current = report.current
        let today = report.today(now: now)
        WeatherSurface(radius:28) {
            HStack(spacing: 18) {
                WeatherSymbol(name: WeatherCondition.symbol(code: current.code, isDay: current.isDay), size: 56)
                    .frame(width: 72)
                Text(WeatherText.temperature(current.temperature))
                    .font(.system(size: 60, weight: .medium, design: .rounded))
                    .fixedSize()
                VStack(alignment: .leading, spacing: 3) {
                    Text(WeatherCondition.description(code: current.code))
                        .font(.system(size: 19, weight: .semibold))
                    Text(summary(current: current, today: today))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    WeatherPlacePicker(model: model)
                        .padding(.top, 3)
                    if let stand {
                        Text(stand).font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 12)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                    GridRow {
                        WeatherStat(symbol: "humidity.fill", label: "Feuchte",
                             value: current.humidity.map(WeatherText.humidity) ?? "–")
                        WeatherStat(symbol: "sunrise.fill", label: "Aufgang",
                             value: today?.sunrise.map { WeatherText.clock($0, calendar: report.calendar) } ?? "–")
                    }
                    GridRow {
                        WeatherStat(symbol: "wind", label: "Wind",
                             value: current.windSpeed.map(WeatherText.wind) ?? "–")
                        WeatherStat(symbol: "sunset.fill", label: "Untergang",
                             value: today?.sunset.map { WeatherText.clock($0, calendar: report.calendar) } ?? "–")
                    }
                }
                // Etwas hoeher als die Mitte: darunter steht die Quellenangabe,
                // sonst klebte sie an "Untergang" (Bildprobe 14.09.).
                .padding(.bottom, 10)
            }
            .padding(.leading, 22)
            .padding(.trailing, 28)
        }
        // Quellenangabe (Lizenz von Open-Meteo und MET Norway): unten rechts
        // unter den Details, wo die Kopfkarte ohnehin Luft hat.
        .overlay(alignment: .bottomTrailing) {
            WeatherAttributionLink(attribution: model.attribution)
                .padding(.trailing, 18)
                .padding(.bottom, 7)
        }
    }

    /// "Gefühlt 17° · H: 22° T: 15°" - was man zur grossen Zahl noch wissen will.
    private func summary(current: CurrentWeather, today: DayForecast?) -> String {
        var parts: [String] = []
        if let feels = current.apparentTemperature {
            parts.append(String(localized: "Gefühlt \(WeatherText.temperature(feels))"))
        }
        if let today { parts.append(WeatherText.range(max: today.maxTemperature, min: today.minTemperature)) }
        return parts.joined(separator: " · ")
    }
}

/// "Wetterdaten: MET Norway" - klein und leise, aber lesbar. Ein Klick
/// oeffnet die Seite des Anbieters (Lizenzen verlangen Name und Link).
private struct WeatherAttributionLink: View {
    let attribution: WeatherAttribution

    var body: some View {
        Link(destination: attribution.url) {
            Text(attribution.text)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help(attribution.url.absoluteString)
    }
}

/// Ein Detail: Symbol, darunter klein die Bezeichnung und fett der Wert
/// (Caelestia: DetailCard/WeatherStat, hier ohne eigene Karte).
private struct WeatherStat: View {
    let symbol: String
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(.secondary)
                .modifier(SymbolContour())
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 14, weight: .semibold)).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Die naechsten 24 Stunden in 12 Spalten zu 2 Stunden: alle 24 einzeln
/// waeren je 35 pt breit, zu eng fuer Symbol und Zahl, und Scrollen geht im
/// nie aktiven Fenster nur per Trackpad.
private struct WeatherHourly: View {
    let slots: [HourSlot]
    let calendar: Calendar

    var body: some View {
        WeatherSurface(radius:24) {
            HStack(spacing: 0) {
                ForEach(slots, id: \.time) { slot in
                    VStack(spacing: 5) {
                        Text(WeatherText.hourLabel(slot.time, isNow: slot.isNow, calendar: calendar))
                            .font(.system(size: 12, weight: slot.isNow ? .semibold : .medium))
                            .foregroundStyle(slot.isNow ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        WeatherSymbol(name: WeatherCondition.symbol(code: slot.code, isDay: slot.isDay), size: 20)
                            .frame(height: 26)
                        WeatherPrecipitation(percent: slot.precipitationProbability)
                        Text(WeatherText.temperature(slot.temperature))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 10)
        }
    }
}

/// Sieben Tage als eigene Kaertchen nebeneinander (Caelestia:
/// forecastRepeater). "Heute" als Akzent-Kapsel, damit der Einstieg sofort
/// auffaellt.
private struct WeatherDaily: View {
    let days: [DayForecast]
    let now: Date
    let calendar: Calendar
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(days, id: \.date) { day in
                let isToday = calendar.isDate(day.date, inSameDayAs: now)
                WeatherSurface(radius:20) {
                    VStack(spacing: 4) {
                        Text(WeatherText.dayLabel(day.date, today: now, calendar: calendar))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isToday ? style.onAccent : Color.primary)
                            .padding(.horizontal, isToday ? 9 : 0)
                            .frame(height: 20)
                            .background(isToday ? style.accent : Color.clear, in: .capsule)
                        Text(WeatherText.shortDate(day.date, calendar: calendar))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        WeatherSymbol(name: WeatherCondition.symbol(code: day.code, isDay: true), size: 24)
                            .frame(height: 32)
                            .padding(.top, 2)
                        WeatherPrecipitation(percent: day.precipitationProbability)
                        HStack(spacing: 6) {
                            Text(WeatherText.temperature(day.maxTemperature))
                            Text(WeatherText.temperature(day.minTemperature)).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
