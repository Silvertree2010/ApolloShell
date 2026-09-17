import ApolloShellCore
import SwiftUI

/// Dashboard wie bei Caelestia (modules/dashboard): Reiterleiste oben,
/// darunter das Kartenraster. Masse aus dem Caelestia-Quellcode (Recherche
/// 14.09.): Aussenabstand 16, Kartenabstand 12, Karten Wetter 275 breit
/// (Radius 42), Benutzer 340 (28), Uhr 110 (16), Kalender (28), Ressourcen
/// (16), Medien 200 (56). Apple-Optik: SF Symbols, Systemschrift, Glas.
///
/// Welche Reiter und Karten wo stehen, bestimmt Nexus > Dashboard
/// (settings.dashboard, `DashboardLayout`); die Ansicht liest es live. Die
/// Flaeche bleibt dabei immer 839 x 392 - die Karten verteilen sich darin
/// nach `DashboardGeometry`.
///
/// Wetter kommt vom gewaehlten Anbieter (WeatherView.swift), Medien ueber den
/// mediaremote-adapter (MediaModel.swift, MediaView.swift).
struct DashboardView: View {
    @Bindable var model: DashboardModel
    let weather: WeatherModel
    let media: MediaModel
    let settings: ShellSettingsStore
    @Namespace private var tabIndicator
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    static let padding: CGFloat = 16
    static let spacing = CGFloat(DashboardGeometry.spacing)
    static let gridWidth = CGFloat(DashboardGeometry.width)
    static let gridHeight = CGFloat(DashboardGeometry.height)
    /// Caelestias Standardkurve: 500 ms, leicht ueberschiessend - fuer den
    /// Reiter-Indikator und fuer Karten, die in Nexus umziehen.
    static let motion = Animation.timingCurve(0.38, 1.21, 0.22, 1, duration: 0.5)

    var body: some View {
        let layout = settings.settings.dashboard
        // In Nexus ausgeblendet, waehrend er gewaehlt war: der erste
        // sichtbare. `Dashboard` zieht `model.tab` beim Oeffnen nach.
        let tab = layout.tabs.resolved(model.tab)
        VStack(spacing: 0) {
            tabBar(tabs: layout.tabs.visible, selected: tab)
            Divider().opacity(0.5)
            Group {
                switch tab {
                case .dashboard: DashboardGrid(cards: layout.cards, model: model, weather: weather, media: media)
                case .media: MediaTab(model: media)
                case .performance: PerformanceView(model: model.performance)
                case .weather: WeatherTab(model: weather)
                }
            }
            .frame(width: Self.gridWidth, height: Self.gridHeight)
            .padding(Self.padding)
        }
        .fixedSize()
    }

    private func tabBar(tabs: [DashboardTab], selected: DashboardTab) -> some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
                    // Caelestia: Indikator 500 ms mit leicht ueberschiessender Kurve.
                    withAnimation(Self.motion) { model.tab = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .symbolVariant(selected == tab ? .fill : .none)
                        Text(tab.title).font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(selected == tab ? style.accent : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .overlay(alignment: .bottom) {
                        if selected == tab {
                            Capsule()
                                .fill(style.accent)
                                .frame(width: 44, height: 3)
                                .matchedGeometryEffect(id: "indicator", in: tabIndicator)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: Self.gridWidth)
        .padding(.horizontal, Self.padding)
        // Ein- und Ausblenden in Nexus gleitet, statt zu springen.
        .animation(Self.motion, value: tabs)
    }
}

// MARK: - Raster

/// Die Karten an ihren Plaetzen. Die Masse rechnet `DashboardGeometry`
/// (getestet in ApolloShellCore); gesetzt werden sie mit denselben Stapeln
/// wie vor dem Baukasten: Reihen links untereinander, die Spalte rechts.
///
/// Warum Stapel und kein eigenes `Layout`, das jede Karte direkt auf ihren
/// Rahmen setzt (so war es zuerst): die Karten lagen gleich, aber innen
/// rechnete SwiftUI anders gerundet - die Kalenderzahl "10" stand bei
/// x = 332.74999999999994 statt 332.75 (gemessen 14.09.). Genau auf der
/// Pixelgrenze (2x: 665,5 px) kippt das um einen ganzen Pixel. Mit denselben
/// Stapeln wie vorher ist Caelestias Anordnung pixelgleich (Bildprobe).
/// Deshalb bekommt die einzige flexible Karte einer Reihe auch wie frueher
/// keine Breite: den Rest verteilt der Stapel, er ist gleich dem gerechneten.
private struct DashboardGrid: View {
    let cards: DashboardCards
    let model: DashboardModel
    let weather: WeatherModel
    let media: MediaModel

    var body: some View {
        let placements = DashboardGeometry.placements(for: cards)
        if placements.isEmpty {
            DashboardEmptyGrid()
        } else {
            let side = placements.filter { $0.zone == .side }
            HStack(alignment: .top, spacing: DashboardView.spacing) {
                if placements.contains(where: { $0.zone.isRow }) {
                    VStack(spacing: DashboardView.spacing) {
                        row(placements.filter { $0.zone == .top })
                        row(placements.filter { $0.zone == .bottom })
                    }
                }
                ForEach(side, id: \.card.kind) { placement in
                    card(placement)
                        .frame(width: placement.frame.width, height: placement.frame.height)
                }
            }
            // Umordnen in Nexus gleitet sichtbar (in der Vorschau), statt zu springen.
            .animation(DashboardView.motion, value: placements.map(\.frame))
        }
    }

    @ViewBuilder
    private func row(_ list: [DashboardPlacement]) -> some View {
        if let height = list.first?.frame.height {
            let flexible = list.filter { $0.card.kind.width(in: $0.zone).isFlexible }
            HStack(spacing: DashboardView.spacing) {
                ForEach(list, id: \.card.kind) { placement in
                    if flexible.count == 1, flexible[0].card.kind == placement.card.kind {
                        card(placement)
                    } else {
                        card(placement).frame(width: placement.frame.width)
                    }
                }
            }
            .frame(height: height)
        }
    }

    private func card(_ placement: DashboardPlacement) -> DashboardCardView {
        DashboardCardView(placement: placement, model: model, weather: weather, media: media)
    }
}

/// Eine Karte nach ihrer Art - die eine Stelle, an der jede Art ihre Ansicht
/// bekommt. Die Form folgt der Flaeche, nicht dem Platz: eine gestreckte
/// Karte in der unteren Reihe ist breit genug, um nebeneinander zu stehen.
/// Die Groesse selbst setzt `DashboardGrid`.
private struct DashboardCardView: View {
    let placement: DashboardPlacement
    let model: DashboardModel
    let weather: WeatherModel
    let media: MediaModel

    var body: some View {
        let size = CGSize(width: placement.frame.width, height: placement.frame.height)
        // Hochkant: hoch genug fuer Symbol ueber Text, zu schmal fuer nebeneinander.
        let upright = size.height >= 200 && size.width < 300
        Group {
            switch placement.card {
            case .weather(let options):
                SmallWeatherCard(model: weather, options: options, vertical: upright)
            case .user(let options):
                UserCard(model: model, options: options, vertical: upright)
            case .clock(let options):
                DateTimeCard(now: model.now, locale: model.calendar.locale ?? .current, options: options)
            case .calendar(let options):
                CalendarCard(model: model, options: options, tall: size.height > 300)
            case .resources(let options):
                ResourcesCard(model: model, options: options, horizontal: size.width > size.height)
            case .media(let options):
                // Rechts (200 x 392) Caelestias Karte; flach und breit ein
                // Streifen; sonst die kleine hochkant.
                if size.width > size.height * 1.3 {
                    MediaStripCard(model: media, options: options, height: size.height)
                } else if size.height >= 330 {
                    MediaDashCard(model: media, options: options)
                } else {
                    MediaCompactCard(model: media, options: options)
                }
            }
        }
    }
}

/// Alle Karten entfernt: ein ruhiger Hinweis statt einer leeren Flaeche.
private struct DashboardEmptyGrid: View {
    var body: some View {
        Card(radius: 28) {
            VStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Keine Karten")
                    .font(.system(size: 15, weight: .semibold))
                Text("In Nexus unter Dashboard lassen sich Karten hinzufügen.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Karte mit leicht abgesetzter Flaeche auf dem Glas. Nicht privat: der
/// Reiter "Leistung" (PerformanceView) nutzt sie auch.
struct Card<Content: View>: View {
    let radius: CGFloat
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        // Mit Theme faerbt `--apollo-card-color` (oder der Verlauf daneben)
        // die Karte, und `--apollo-card-radius` rundet sie.
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

// MARK: - Karten

/// Initiale, Name und zwei Kapseln. Hochkant (untere Reihe, Spalte) steht
/// die Initiale ueber dem Namen.
private struct UserCard: View {
    let model: DashboardModel
    var options = DashboardUserOptions()
    var vertical = false
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        Card(radius: 28) {
            if vertical {
                VStack(spacing: 12) {
                    avatar(size: 64)
                    VStack(spacing: 6) {
                        Text(model.userName).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        badges
                    }
                }
                .padding(.horizontal, 14)
            } else {
                HStack(spacing: 14) {
                    avatar(size: 72)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.userName).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                        badges
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func avatar(size: CGFloat) -> some View {
        Text(String(model.userName.prefix(1)))
            .font(.system(size: size * 30 / 72, weight: .semibold, design: .rounded))
            .foregroundStyle(style.onAccent)
            .frame(width: size, height: size)
            .background(style.accent, in: .circle)
    }

    @ViewBuilder private var badges: some View {
        if options.showSystem {
            Badge(symbol: "apple.logo", text: model.systemVersion)
        }
        if options.showUptime {
            Badge(symbol: "clock.arrow.circlepath", text: String(localized: "läuft seit \(model.uptime)"))
        }
    }
}

private struct Badge: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.07), in: .capsule)
    }
}

/// Uhr wie Caelestia: Stunde, drei Punkte, Minute untereinander - oder
/// "14:05" in einer Zeile. Das Datum darunter auf Wunsch.
private struct DateTimeCard: View {
    let now: Date
    let locale: Locale
    var options = DashboardClockOptions()

    var body: some View {
        Card(radius: 16) {
            VStack(spacing: 12) {
                clock
                if options.showDate {
                    // Als fertiger Text: `Text(_:format:)` nimmt die Sprache
                    // der Umgebung statt der im Format (Bildprobe: "Monday")
                    // - so passt das Datum zu den Wochentagen im Kalender.
                    VStack(spacing: 1) {
                        Text(now.formatted(.dateTime.weekday(.wide).locale(locale)))
                            .font(.system(size: 12, weight: .semibold))
                        Text(now.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
        }
    }

    @ViewBuilder private var clock: some View {
        switch options.style {
        case .stacked:
            VStack(spacing: 6) {
                Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                Text("•••").font(.system(size: 14, weight: .bold)).foregroundStyle(.secondary)
                Text(now, format: .dateTime.minute(.twoDigits))
            }
            .font(.system(size: 30, weight: .semibold, design: .rounded))
            .monospacedDigit()
        case .inline:
            Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// Monat mit heute markiert (Caelestia: DayOfWeekRow + MonthGrid). Erster
/// Wochentag und Kalenderwochen aus den Optionen; die Sprache bleibt die des
/// Modells.
private struct CalendarCard: View {
    let model: DashboardModel
    var options = DashboardCalendarOptions()
    /// Ueber die ganze Hoehe (obere Reihe leer): Zeilen weiter auseinander.
    var tall = false
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        let calendar = options.applied(to: model.calendar)
        Card(radius: 28) {
            VStack(spacing: tall ? 16 : 8) {
                HStack {
                    Button { model.showMonth(offset: -1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(model.shownMonth, format: .dateTime.month(.wide).year().locale(model.calendar.locale ?? .current))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button { model.showMonth(offset: 1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                let weeks = CalendarMonth.weeks(for: model.shownMonth, today: model.now, calendar: calendar)
                let numbers = options.showWeekNumbers ? CalendarMonth.weekNumbers(weeks, calendar: calendar) : []
                Grid(horizontalSpacing: 4, verticalSpacing: tall ? 14 : 2) {
                    GridRow {
                        if options.showWeekNumbers {
                            Text("KW").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        ForEach(CalendarMonth.weekdaySymbols(calendar: calendar), id: \.self) { symbol in
                            Text(symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(weeks.indices, id: \.self) { week in
                        GridRow {
                            if options.showWeekNumbers {
                                Text("\(numbers[week])")
                                    .font(.system(size: 10, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.tertiary)
                                    .accessibilityLabel("Kalenderwoche \(numbers[week])")
                            }
                            ForEach(weeks[week], id: \.self) { day in
                                Text("\(day.day)")
                                    .font(.system(size: 12, weight: day.isToday ? .bold : .regular))
                                    .foregroundStyle(day.isToday ? style.onAccent : day.inMonth ? Color.primary : Color.secondary.opacity(0.5))
                                    .frame(width: 26, height: 26)
                                    .background(day.isToday ? style.accent : Color.clear, in: .circle)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }
}

/// Ringe fuer CPU, RAM, Speicher (Caelestia: CircularProgress, Strich 6) -
/// untereinander in der schmalen Karte, nebeneinander in der oberen Reihe.
private struct ResourcesCard: View {
    let model: DashboardModel
    var options = DashboardResourcesOptions()
    var horizontal = false

    var body: some View {
        Card(radius: 16) {
            if horizontal {
                HStack(spacing: 16) { rings }
            } else {
                VStack(spacing: 14) { rings }
            }
        }
    }

    @ViewBuilder private var rings: some View {
        if options.showCPU { Ring(value: model.cpu, symbol: "cpu", help: "CPU") }
        if options.showMemory { Ring(value: model.memory, symbol: "memorychip", help: String(localized: "Arbeitsspeicher")) }
        if options.showStorage { Ring(value: model.storage, symbol: "internaldrive", help: String(localized: "Speicher")) }
    }
}

private struct Ring: View {
    let value: Double
    let symbol: String
    let help: String
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: 6)
            Circle()
                .trim(from: 0, to: value)
                .stroke(style.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: value)
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
        }
        .frame(width: 56, height: 56)
        .help("\(help) \(Int((value * 100).rounded())) %")
        .accessibilityLabel("\(help) \(Int((value * 100).rounded())) Prozent")
    }
}
