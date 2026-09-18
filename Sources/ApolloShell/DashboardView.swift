import ApolloShellCore
import SwiftUI

/// Dashboard wie bei Caelestia (modules/dashboard): Seitenleiste oben,
/// darunter die gewaehlte Seite. Masse aus dem Caelestia-Quellcode
/// (Recherche 14.09.): Aussenabstand 16, Kartenabstand 12, Karten Wetter 275
/// breit (Radius 42), Benutzer 340 (28), Uhr 110 (16), Kalender (28),
/// Ressourcen (16), Medien 200 (56). Apple-Optik: SF Symbols, Systemschrift,
/// Glas.
///
/// Welche Seiten es gibt und was auf ihnen liegt, bestimmt
/// `settings.dashboardPages` (`DashboardPages`, Nexus > Dashboard); die
/// Ansicht liest es live. Die Flaeche bleibt dabei immer 839 x 392 - die
/// Widgets stehen darin an ihren eigenen Rahmen (`BentoPageView`).
///
/// Wetter kommt je Widget aus einem eigenen `WeatherModel`
/// (`WeatherModels.swift`), Medien ueber den mediaremote-adapter
/// (MediaModel.swift, MediaView.swift).
struct DashboardView: View {
    @Bindable var model: DashboardModel
    let weatherModels: WeatherModels
    let media: MediaModel
    let settings: ShellSettingsStore
    let editor: DashboardEditor
    @Namespace private var tabIndicator
    @Environment(\.shellStyle) private var style

    static let padding: CGFloat = 16
    static let spacing = CGFloat(DashboardGeometry.spacing)
    static let gridWidth = CGFloat(DashboardGeometry.width)
    static let gridHeight = CGFloat(DashboardGeometry.height)
    /// Caelestias Standardkurve: 500 ms, leicht ueberschiessend - fuer den
    /// Reiter-Indikator und fuer Widgets, die in Nexus umziehen.
    static let motion = Animation.shellSpatial
    /// Mindestbreite eines Reiters in der scrollenden Leiste (viele Seiten).
    static let tabWidth: CGFloat = 96

    /// Die Seiten - waehrend einer Bearbeitung deren Arbeitskopie, sonst aus
    /// den Einstellungen, sonst (noch nicht migriert, etwa in Nexus vor dem
    /// ersten Start) die vier mitgelieferten.
    private var pages: DashboardPages {
        editor.session?.pages ?? settings.settings.dashboardPages
            ?? DashboardPages(pages: DashboardPages.defaultPages(places: .empty,
                                                                  hasBattery: PerformanceSampler.hasInternalBattery))!
    }

    var body: some View {
        let pages = pages
        let selectedID = editor.session?.pageID ?? model.pageID
        let selected = selectedID.flatMap(pages.page(id:)) ?? pages.pages[0]
        // Skaliert um die obere linke Ecke (Kantenfenster oben) - die
        // Referenzgroesse (Massstab 1) rechnet `ScaledToFit` selbst aus
        // `content.fixedSize()`, so bleibt ihr Ergebnis (auch bei
        // Massstab 1) bitgleich mit `.fixedSize()` allein.
        ScaledToFit(scale: model.scale) {
            content(pages: pages, selected: selected)
                .scaleEffect(model.scale, anchor: .topLeading)
        }
        // Ein Wechsel der Seite (auch aus `Dashboard.show(tab:)`) zieht nach,
        // ob die Leistungs-Messung laufen soll.
        .onChange(of: selected.id, initial: true) { _, _ in
            model.showsPerformance = selected.widgets.contains { $0.kind.isPerformance }
        }
    }

    private func content(pages: DashboardPages, selected: DashboardPage) -> some View {
        VStack(spacing: 0) {
            pageBar(pages: pages.pages, selected: selected)
            Divider().opacity(0.5)
            BentoPageView(page: selected, context: WidgetContext(dashboard: model, media: media,
                                                                  weather: weatherModels.model(for:)), editor: editor)
                .frame(width: Self.gridWidth, height: Self.gridHeight)
                .padding(Self.padding)
        }
        .fixedSize()
    }

    /// Solange jede Seite mindestens `tabWidth` breit stehen kann, wie
    /// bisher gleichmaessig ueber die ganze Breite verteilt; sonst rollend,
    /// mit der gewaehlten Seite im Blick.
    @ViewBuilder
    private func pageBar(pages: [DashboardPage], selected: DashboardPage) -> some View {
        if CGFloat(pages.count) * Self.tabWidth <= Self.gridWidth {
            HStack(spacing: 0) {
                ForEach(pages) { page in
                    pageButton(page, selected: selected).frame(maxWidth: .infinity)
                }
            }
            .frame(width: Self.gridWidth)
            .padding(.horizontal, Self.padding)
            .animation(Self.motion, value: pages.map(\.id))
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(pages) { page in
                            pageButton(page, selected: selected).frame(width: Self.tabWidth).id(page.id)
                        }
                    }
                }
                .frame(width: Self.gridWidth)
                .padding(.horizontal, Self.padding)
                .onChange(of: selected.id) { _, id in
                    withAnimation(Self.motion) { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .animation(Self.motion, value: pages.map(\.id))
        }
    }

    private func pageButton(_ page: DashboardPage, selected: DashboardPage) -> some View {
        Button {
            // Caelestia: Indikator 500 ms mit leicht ueberschiessender Kurve.
            // Waehrend einer Bearbeitung wechselt die Sitzung die Seite -
            // Nexus folgt, weil es dasselbe `editor`-Objekt beobachtet.
            withAnimation(Self.motion) {
                if editor.isEditing { editor.pageID = page.id } else { model.pageID = page.id }
            }
        } label: {
            VStack(spacing: 4) {
                // Theme: icons/panel-media.png, panel-performance.png,
                // panel-weather.png; die Seite Dashboard nimmt bar-dashboard.
                // Eigene Seiten haben keine Theme-Kennung, nur ihr Symbol.
                Group {
                    if let template = page.template {
                        ThemedIcon(template.tab.iconID, fallback: page.symbol)
                    } else {
                        Image(systemName: page.symbol)
                    }
                }
                .font(style.font(size: 16, weight: .medium))
                .symbolVariant(page.id == selected.id ? .fill : .none)
                .frame(width: 18, height: 18)
                Text(page.name).font(style.font(size: 12, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(page.id == selected.id ? style.accent : Color.secondary)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                if page.id == selected.id {
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

/// Bemisst ihren Inhalt unskaliert (`sizeThatFits(.unspecified)`, dasselbe,
/// was `.fixedSize()` allein auch tut) und meldet dem Elternelement diese
/// Groesse mal `scale` - der Inhalt selbst traegt sein eigenes
/// `.scaleEffect(scale, anchor: .topLeading)`. So bleibt die gemeldete
/// Flaeche (Kantenfenster, `RenderMode`, Nexus-Vorschau) genau so gross wie
/// das skaliert gezeichnete Ergebnis, ohne die unskalierte Groesse von
/// aussen kennen zu muessen - und bei `scale == 1` bitgleich mit
/// `.fixedSize()` allein.
private struct ScaledToFit: Layout {
    let scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let ideal = subview.sizeThatFits(.unspecified)
        return CGSize(width: ideal.width * scale, height: ideal.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let ideal = subview.sizeThatFits(.unspecified)
        subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(ideal))
    }
}

// MARK: - Karten

/// Initiale, Name und zwei Kapseln. Hochkant (untere Reihe, Spalte) steht
/// die Initiale ueber dem Namen.
struct UserCard: View {
    let model: DashboardModel
    var options = DashboardUserOptions()
    var vertical = false
    @Environment(\.shellStyle) private var style

    var body: some View {
        Card(radius: 28) {
            if vertical {
                VStack(spacing: 12) {
                    avatar(size: 64)
                    VStack(spacing: 6) {
                        Text(model.userName).font(style.font(size: 16, weight: .semibold)).lineLimit(1)
                        badges
                    }
                }
                .padding(.horizontal, 14)
            } else {
                HStack(spacing: 14) {
                    avatar(size: 72)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.userName).font(style.font(size: 17, weight: .semibold)).lineLimit(1)
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
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(style.font(size: 10, weight: .semibold))
            Text(text).font(style.font(size: 11, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.07), in: .capsule)
    }
}

/// Uhr wie Caelestia: Stunde, drei Punkte, Minute untereinander - oder
/// "14:05" in einer Zeile. Das Datum darunter auf Wunsch.
struct DateTimeCard: View {
    let now: Date
    let locale: Locale
    var options = DashboardClockOptions()
    @Environment(\.shellStyle) private var style

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
                            .font(style.font(size: 12, weight: .semibold))
                        Text(now.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
                            .font(style.font(size: 11, weight: .medium))
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
                Text("•••").font(style.font(size: 14, weight: .bold)).foregroundStyle(.secondary)
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
struct CalendarCard: View {
    let model: DashboardModel
    var options = DashboardCalendarOptions()
    /// Ueber die ganze Hoehe (obere Reihe leer): Zeilen weiter auseinander.
    var tall = false
    @Environment(\.shellStyle) private var style

    var body: some View {
        let calendar = options.applied(to: model.calendar)
        Card(radius: 28) {
            VStack(spacing: tall ? 16 : 8) {
                HStack {
                    Button { model.showMonth(offset: -1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(model.shownMonth, format: .dateTime.month(.wide).year().locale(model.calendar.locale ?? .current))
                        .font(style.font(size: 14, weight: .semibold))
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
                            Text("KW").font(style.font(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        ForEach(CalendarMonth.weekdaySymbols(calendar: calendar), id: \.self) { symbol in
                            Text(symbol).font(style.font(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(weeks.indices, id: \.self) { week in
                        GridRow {
                            if options.showWeekNumbers {
                                Text("\(numbers[week])")
                                    .font(style.font(size: 10, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.tertiary)
                                    .accessibilityLabel("Kalenderwoche \(numbers[week])")
                            }
                            ForEach(weeks[week], id: \.self) { day in
                                Text("\(day.day)")
                                    .font(style.font(size: 12, weight: day.isToday ? .bold : .regular))
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
struct ResourcesCard: View {
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
        if options.showCPU { Ring(value: model.cpu, symbol: "cpu", iconID: "panel-cpu", help: "CPU") }
        if options.showMemory { Ring(value: model.memory, symbol: "memorychip", iconID: "panel-memory", help: String(localized: "Arbeitsspeicher")) }
        if options.showStorage { Ring(value: model.storage, symbol: "internaldrive", iconID: "panel-disk", help: String(localized: "Speicher")) }
    }
}

private struct Ring: View {
    let value: Double
    let symbol: String
    /// Kennung fuer den Symbol-Austausch im Theme.
    var iconID: String = ""
    let help: String
    @Environment(\.shellStyle) private var style

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: 6)
            Circle()
                .trim(from: 0, to: value)
                .stroke(style.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: value)
            ThemedIcon(iconID.isEmpty ? symbol : iconID, fallback: symbol)
                .font(style.font(size: 14, weight: .medium))
                .frame(width: 16, height: 16)
        }
        .frame(width: 56, height: 56)
        .help("\(help) \(Int((value * 100).rounded())) %")
        .accessibilityLabel("\(help) \(Int((value * 100).rounded())) Prozent")
    }
}
