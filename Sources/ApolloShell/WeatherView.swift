import ApolloShellCore
import SwiftUI

// The weather in the dashboard, after Caelestia
// (modules/dashboard/dash/SmallWeather.qml and
// modules/dashboard/WeatherTab.qml) in an Apple look: SF Symbols in multicolor
// instead of Material icons, SF Rounded for the big numbers.
//
// Both views run in a TimelineView once a minute: "Now" in the hour row,
// "Today" and "As of" hang on the clock, not only on new data.

/// The card in the dashboard grid (Caelestia: a 275 x 130 slot, radius 42):
/// the symbol on the left, next to it the temperature and the condition, as a
/// group in the middle as in Caelestia. In portrait (the bottom row, the side
/// column) the symbol stands above the numbers - side by side it did not fit
/// into 200 points of width.
/// Not `WeatherCard`: that is the name of the placeholder in
/// DashboardView.swift, and two types of one name in the module are a mistake.
struct SmallWeatherCard: View {
    let model: WeatherModel
    /// Nexus > Dashboard; the default shows everything as in Caelestia.
    var options = DashboardWeatherOptions()
    var vertical = false
    @Environment(\.shellStyle) private var style

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = model.fixedNow ?? context.date
            Card(radius:42) {
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
        // The source here too, only as a note: the card is too small for a
        // line of its own, and the tab shows it visibly.
        .help(helpText)
        // No switcher of its own as with the hero: a click jumps to the next
        // favourite - only with several, otherwise it would stay on the same
        // place (an unchanged image). Without effect while editing:
        // `EditableWidgetView` switches clicks off there (`allowsHitTesting`).
        .contentShape(Rectangle())
        .onTapGesture { selectNextPlace() }
    }

    private func selectNextPlace() {
        let locations = model.favorites.locations
        guard locations.count > 1, let current = model.location,
              let index = locations.firstIndex(of: current) else { return }
        model.select(locations[(index + 1) % locations.count])
    }

    private var helpText: String {
        guard let location = model.location else { return "Set Location in Nexus" }
        guard model.report != nil else { return "Weather in \(location.name)" }
        return "Wetter in \(location.name) · \(model.attribution.text)"
    }

    /// The symbol and the numbers; the caller decides side by side or stacked.
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
                        .font(style.font(size: 13, weight: .medium))
                        .lineLimit(2)
                }
                if options.showRange, let today = report.today(now: now) {
                    Text(WeatherText.range(max: today.maxTemperature, min: today.minTemperature))
                        .font(style.font(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let stand = model.standText(now: now) {
                    Text(stand).font(style.font(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)
        } else if model.location == nil {
            WeatherSymbol(name: "location.slash", size: 40, placeholder: true)
            VStack(alignment: alignment, spacing: 2) {
                Button("Set Location in Nexus") { model.onOpenNexus() }
                    .buttonStyle(.plain)
                    .font(style.font(size: 12, weight: .semibold))
                    .foregroundStyle(style.accent)
            }
        } else {
            WeatherSymbol(name: "cloud.sun", size: 40, placeholder: true)
            VStack(alignment: alignment, spacing: 2) {
                Text("--°").font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(model.lastAttemptFailed ? String(localized: "No Weather Data") : String(localized: "Loading…"))
                    .font(style.font(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Building blocks

/// The weather symbol in multicolor (the sun yellow, the rain blue). The
/// placeholder stays grey, so "nothing there yet" does not look like weather.
private struct WeatherSymbol: View {
    let name: String
    let size: CGFloat
    var placeholder = false
    @Environment(\.shellStyle) private var style

    var body: some View {
        Image(systemName: name)
            .font(style.font(size: size))
            .symbolRenderingMode(placeholder ? .hierarchical : .multicolor)
            .foregroundStyle(placeholder ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .modifier(SymbolContour())
            .accessibilityHidden(true)
    }
}

/// Multicolor weather symbols have white clouds, snowflakes and horizon lines
/// - almost invisible on the light card (image sample 14.09.). In the light
/// they therefore get a fine shadow as an outline; in the dark they stand on
/// their own.
private struct SymbolContour: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(colorScheme == .light ? 0.3 : 0), radius: 0.8, y: 0.4)
    }
}

/// The chance of rain in blue as in Apple Weather; darker in the light,
/// otherwise cyan disappears on the light card. Below 20 % the line stays
/// empty but keeps its height, so that the columns stay flush.
private struct WeatherPrecipitation: View {
    let percent: Int?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellStyle) private var style

    var body: some View {
        Text(WeatherText.precipitation(percent) ?? " ")
            .font(style.font(size: 10, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? Color.cyan : Color.blue)
            .frame(height: 12)
    }
}

// MARK: - Tab

/// The place choice as capsules, out of the favourites (Nexus > Dashboard):
/// the chosen one in the accent color.
private struct WeatherPlacePicker: View {
    let favorites: WeatherFavorites
    let selected: WeatherLocation?
    let select: (WeatherLocation) -> Void
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack(spacing: 5) {
            ForEach(favorites.locations) { place in
                let isSelected = place == selected
                Button {
                    select(place)
                } label: {
                    Text(place.name)
                        .font(style.font(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .foregroundStyle(isSelected ? AnyShapeStyle(style.onAccent) : AnyShapeStyle(.secondary))
                        .background(
                            isSelected ? AnyShapeStyle(style.accent) : AnyShapeStyle(Color.primary.opacity(0.08)),
                            in: .capsule
                        )
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .help("Weather for \(place.name)")
            }
        }
        .fixedSize()
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

struct WeatherHero: View {
    let report: WeatherReport
    let model: WeatherModel
    let now: Date
    let stand: String?
    @Environment(\.shellStyle) private var style

    var body: some View {
        let current = report.current
        let today = report.today(now: now)
        Card(radius:28) {
            HStack(spacing: 18) {
                WeatherSymbol(name: WeatherCondition.symbol(code: current.code, isDay: current.isDay), size: 56)
                    .frame(width: 72)
                Text(WeatherText.temperature(current.temperature))
                    .font(.system(size: 60, weight: .medium, design: .rounded))
                    .fixedSize()
                VStack(alignment: .leading, spacing: 3) {
                    Text(WeatherCondition.description(code: current.code))
                        .font(style.font(size: 19, weight: .semibold))
                    Text(summary(current: current, today: today))
                        .font(style.font(size: 13))
                        .foregroundStyle(.secondary)
                    WeatherPlacePicker(favorites: model.favorites, selected: model.location, select: model.select)
                        .padding(.top, 3)
                    if let stand {
                        Text(stand).font(style.font(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 12)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                    GridRow {
                        WeatherStat(symbol: "humidity.fill", label: "Humidity",
                             value: current.humidity.map(WeatherText.humidity) ?? "–")
                        WeatherStat(symbol: "sunrise.fill", label: "Sunrise",
                             value: today?.sunrise.map { WeatherText.clock($0, calendar: report.calendar) } ?? "–")
                    }
                    GridRow {
                        WeatherStat(symbol: "wind", label: "Wind",
                             value: current.windSpeed.map(WeatherText.wind) ?? "–")
                        WeatherStat(symbol: "sunset.fill", label: "Sunset",
                             value: today?.sunset.map { WeatherText.clock($0, calendar: report.calendar) } ?? "–")
                    }
                }
                // A little above the middle: the source note stands below it,
                // otherwise it would stick to "Sunset" (image sample 14.09.).
                .padding(.bottom, 10)
            }
            .padding(.leading, 22)
            .padding(.trailing, 28)
        }
        // The source note (the licence of Open-Meteo and MET Norway): at the
        // bottom right below the details, where the header card has room anyway.
        .overlay(alignment: .bottomTrailing) {
            WeatherAttributionLink(attribution: model.attribution)
                .padding(.trailing, 18)
                .padding(.bottom, 7)
        }
    }

    /// "Feels like 17° · H: 22° L: 15°" - what one wants next to the big number.
    private func summary(current: CurrentWeather, today: DayForecast?) -> String {
        var parts: [String] = []
        if let feels = current.apparentTemperature {
            parts.append(String(localized: "Feels like \(WeatherText.temperature(feels))"))
        }
        if let today { parts.append(WeatherText.range(max: today.maxTemperature, min: today.minTemperature)) }
        return parts.joined(separator: " · ")
    }
}

/// "Weather data: MET Norway" - small and quiet, but readable. A click opens
/// the page of the provider (the licences ask for a name and a link).
private struct WeatherAttributionLink: View {
    let attribution: WeatherAttribution
    @Environment(\.shellStyle) private var style

    var body: some View {
        Link(destination: attribution.url) {
            Text(attribution.text)
                .font(style.font(size: 10))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help(attribution.url.absoluteString)
    }
}

/// One detail: a symbol, below it the label in small and the value in bold
/// (Caelestia: DetailCard/WeatherStat, here without a card of its own).
private struct WeatherStat: View {
    let symbol: String
    let label: LocalizedStringKey
    let value: String
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(style.font(size: 16))
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(.secondary)
                .modifier(SymbolContour())
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(style.font(size: 11)).foregroundStyle(.secondary)
                Text(value).font(style.font(size: 14, weight: .semibold)).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The next 24 hours in 12 columns of 2 hours: all 24 on their own would be
/// 35 pt wide each, too tight for a symbol and a number, and scrolling in a
/// window that is never active only works with a trackpad.
struct WeatherHourly: View {
    let slots: [HourSlot]
    let calendar: Calendar
    @Environment(\.shellStyle) private var style

    var body: some View {
        Card(radius:24) {
            HStack(spacing: 0) {
                ForEach(slots, id: \.time) { slot in
                    VStack(spacing: 5) {
                        Text(WeatherText.hourLabel(slot.time, isNow: slot.isNow, calendar: calendar))
                            .font(style.font(size: 12, weight: slot.isNow ? .semibold : .medium))
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

/// Seven days as small cards side by side (Caelestia: forecastRepeater).
/// "Today" as an accent capsule, so that the start stands out right away.
/// auffaellt.
struct WeatherDaily: View {
    let days: [DayForecast]
    let now: Date
    let calendar: Calendar
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack(spacing: 12) {
            ForEach(days, id: \.date) { day in
                let isToday = calendar.isDate(day.date, inSameDayAs: now)
                Card(radius:20) {
                    VStack(spacing: 4) {
                        Text(WeatherText.dayLabel(day.date, today: now, calendar: calendar))
                            .font(style.font(size: 13, weight: .semibold))
                            .foregroundStyle(isToday ? style.onAccent : Color.primary)
                            .padding(.horizontal, isToday ? 9 : 0)
                            .frame(height: 20)
                            .background(isToday ? style.accent : Color.clear, in: .capsule)
                        Text(WeatherText.shortDate(day.date, calendar: calendar))
                            .font(style.font(size: 11))
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
