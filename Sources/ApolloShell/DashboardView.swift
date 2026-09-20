import ApolloShellCore
import SwiftUI

/// Dashboard like Caelestia's (modules/dashboard): tab bar on top, the
/// selected page below it. Measurements from the Caelestia source code
/// (research 09/14): outer padding 16, card spacing 12, weather card 275
/// wide (radius 42), user 340 (28), clock 110 (16), calendar (28),
/// resources (16), media 200 (56). Apple look: SF Symbols, system font,
/// glass.
///
/// Which pages exist and what lies on them is determined by
/// `settings.dashboardPages` (`DashboardPages`, Nexus > Dashboard); the
/// view reads it live. The area itself always stays 839 x 392 - the
/// widgets sit inside it at their own frames (`BentoPageView`).
///
/// Weather comes per widget from its own `WeatherModel`
/// (`WeatherModels.swift`), media via the mediaremote-adapter
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
    /// Caelestia's standard curve: 500 ms, slightly overshooting - for the
    /// tab indicator and for widgets moving into Nexus.
    static let motion = Animation.shellSpatial
    /// Minimum width of a tab in the scrolling bar (many pages).
    static let tabWidth: CGFloat = 96
    static let rootSpace = "dashboardRoot"

    /// The pages - during an edit their working copy, otherwise from the
    /// settings, otherwise (not yet migrated, e.g. in Nexus before the
    /// first launch) the four bundled ones.
    private var pages: DashboardPages {
        editor.session?.pages ?? settings.settings.dashboardPages
            ?? DashboardPages(pages: DashboardPages.defaultPages(places: .empty,
                                                                  hasBattery: PerformanceSampler.hasInternalBattery))!
    }

    var body: some View {
        let pages = pages
        let selectedID = editor.session?.pageID ?? model.pageID
        let selected = selectedID.flatMap(pages.page(id:)) ?? pages.pages[0]
        // Scaled around the top-left corner (edge window on top) - the
        // reference size (scale 1) is computed by `ScaledToFit` itself
        // from `content.fixedSize()`, so its result (even at scale 1)
        // stays bit-identical with `.fixedSize()` alone.
        ScaledToFit(scale: model.scale) {
            content(pages: pages, selected: selected)
                .scaleEffect(model.scale, anchor: .topLeading)
        }
        // Coordinate space of the whole view (top left, scaled) - only
        // for the self-test of edit mode (`debugPageRectInHost`).
        .coordinateSpace(name: Self.rootSpace)
        // A change in the shown widgets (page change - also from
        // `Dashboard.show(tab:)` or during an edit -, or a widget dropped
        // on/removed from the same page) re-checks whether the
        // performance measurement should run, and restarts the weather
        // models of the now-shown weather widgets, as long as open.
        .onChange(of: PageWidgetsKey(page: selected), initial: true) { _, key in
            model.showsPerformance = key.kinds.contains { $0.isPerformance }
            if model.isOpen {
                weatherModels.start(for: selected.widgets.filter { $0.kind.usesPlaces })
            }
        }
    }

    /// Comparison value for `.onChange`: changes on every switch of the
    /// shown page and on every change of its widgets (kind or identifier)
    /// - not on mere option changes (e.g. locations).
    private struct PageWidgetsKey: Equatable {
        let pageID: DashboardPage.ID
        let kinds: [WidgetKind]
        let widgetIDs: [WidgetInstance.ID]

        init(page: DashboardPage) {
            pageID = page.id
            kinds = page.widgets.map(\.kind)
            widgetIDs = page.widgets.map(\.id)
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

    /// As long as every page can stand at least `tabWidth` wide, spread
    /// evenly across the full width as before; otherwise scrolling, with
    /// the selected page in view. During editing (task 4) a **+** is
    /// added at the end, which creates and shows a new page.
    @ViewBuilder
    private func pageBar(pages: [DashboardPage], selected: DashboardPage) -> some View {
        let extra: CGFloat = editor.isEditing ? Self.tabWidth : 0
        if CGFloat(pages.count) * Self.tabWidth + extra <= Self.gridWidth {
            HStack(spacing: 0) {
                ForEach(pages) { page in
                    pageButton(page, selected: selected).frame(maxWidth: .infinity)
                }
                if editor.isEditing { addPageButton.frame(width: Self.tabWidth) }
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
                        if editor.isEditing { addPageButton.frame(width: Self.tabWidth) }
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

    /// Menu instead of a plain button (task 7): "New Page" as before,
    /// plus "Restore Default Pages" for the bundled pages that the old
    /// Nexus page list still offered before task 7. Disabled once all
    /// four already exist (`DashboardEditor.isMissingDefaultPages`).
    private var addPageButton: some View {
        Menu {
            Button("New Page") {
                withAnimation(Self.motion) { _ = editor.addPage() }
            }
            Button("Restore Default Pages") {
                withAnimation(Self.motion) { editor.restoreDefaults() }
            }
            .disabled(!editor.isMissingDefaultPages)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(style.font(size: 16, weight: .medium))
                    .frame(width: 18, height: 18)
                Text(" ").font(style.font(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Add Page")
        .accessibilityLabel("Add Page")
    }

    @FocusState private var renameFieldFocused: Bool

    @ViewBuilder
    private func pageButton(_ page: DashboardPage, selected: DashboardPage) -> some View {
        if editor.isEditing, editor.renamingPageID == page.id {
            renameField(page, selected: selected)
        } else {
            pageTab(page, selected: selected)
        }
    }

    /// Renaming: the field stands on its own instead of inside the tab
    /// button's label - there, the button got every click (page switch),
    /// the field never got focus (live test 09/19).
    private func renameField(_ page: DashboardPage, selected: DashboardPage) -> some View {
        VStack(spacing: 4) {
            Image(systemName: page.symbol)
                .font(style.font(size: 16, weight: .medium))
                .frame(width: 18, height: 18)
            TextField("Name", text: Binding(
                get: { page.name },
                set: { editor.renamePage(page.id, to: $0) }
            ))
            .textFieldStyle(.plain)
            .font(style.font(size: 12, weight: .medium))
            .multilineTextAlignment(.center)
            .focused($renameFieldFocused)
            .onSubmit { editor.renamingPageID = nil }
            .onAppear { renameFieldFocused = true }
            .padding(.horizontal, 6)
            .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 5))
        }
        .foregroundStyle(style.accent)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func pageTab(_ page: DashboardPage, selected: DashboardPage) -> some View {
        Button {
            // Caelestia: indicator 500 ms with a slightly overshooting
            // curve. During an edit, the session switches the page -
            // Nexus follows, because it observes the same `editor` object.
            withAnimation(Self.motion) {
                if editor.isEditing { editor.pageID = page.id } else { model.pageID = page.id }
            }
        } label: {
            VStack(spacing: 4) {
                // Theme: icons/panel-media.png, panel-performance.png,
                // panel-weather.png; the Dashboard page uses bar-dashboard.
                // Custom pages have no theme identifier, only their symbol.
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
        // Context menu only while editing (task 4): rename, icon,
        // duplicate, delete (never the last page - `DashboardEditor`
        // does not allow it anyway, the button still stays visible so the
        // menu does not look different for every page).
        .contextMenu {
            if editor.isEditing {
                Button("Rename") { editor.renamingPageID = page.id }
                Menu("Icon") {
                    ForEach(nexusPageSymbols, id: \.self) { symbol in
                        Button {
                            editor.setSymbol(symbol, forPage: page.id)
                        } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                }
                Button("Duplicate") { editor.duplicatePage(page.id) }
                // Without confirmation: a `.alert` hangs as a sheet off
                // the borderless edge window at the top of the screen and
                // did not appear reliably there - and the whole edit can
                // be undone with "Cancel" anyway.
                Button("Delete", role: .destructive) { withAnimation(Self.motion) { _ = editor.removePage(page.id) } }
                    .disabled((editor.session?.pages.pages.count ?? 0) <= 1)
            }
        }
    }
}

/// Measures its content unscaled (`sizeThatFits(.unspecified)`, the same
/// thing `.fixedSize()` alone also does) and reports this size times
/// `scale` to the parent - the content itself carries its own
/// `.scaleEffect(scale, anchor: .topLeading)`. This way the reported area
/// (edge window, `RenderMode`, Nexus preview) stays exactly as large as
/// the scaled, drawn result, without needing to know the unscaled size
/// from outside - and at `scale == 1` bit-identical with `.fixedSize()`
/// alone.
struct ScaledToFit: Layout {
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

// MARK: - Cards

/// Initial, name, and two badges. Portrait (bottom row, column): the
/// initial sits above the name.
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
            Badge(symbol: "clock.arrow.circlepath", text: String(localized: "running since \(model.uptime)"))
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

/// Clock like Caelestia: hour, three dots, minute stacked - or "14:05" on
/// one line. The date below it on request.
struct DateTimeCard: View {
    let now: Date
    let locale: Locale
    var options = DashboardClockOptions()
    @Environment(\.shellStyle) private var style

    /// Time zone from the options (`nil` = the system's) - affects both
    /// clock and date, so a chosen city really shows its own time.
    private var timeZone: TimeZone { options.resolvedTimeZone }

    var body: some View {
        Card(radius: 16) {
            VStack(spacing: 12) {
                clock
                if options.showDate {
                    // As finished text: `Text(_:format:)` uses the
                    // environment's language instead of the one in the
                    // format (image sample: "Monday") - so the date
                    // matches the weekdays in the calendar. Time zone
                    // comes from `.environment(\.timeZone, ...)` below
                    // (SwiftUI applies it to `Text(_:format:)`).
                    VStack(spacing: 1) {
                        Text(now, format: .dateTime.weekday(.wide).locale(locale))
                            .font(style.font(size: 12, weight: .semibold))
                        Text(now, format: .dateTime.day().month(.abbreviated).locale(locale))
                            .font(style.font(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
        }
        .environment(\.timeZone, timeZone)
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

/// Month with today marked (Caelestia: DayOfWeekRow + MonthGrid). First
/// weekday and week numbers from the options; the language stays that of
/// the model.
struct CalendarCard: View {
    let model: DashboardModel
    var options = DashboardCalendarOptions()
    /// Over the full height (top row empty): rows spaced further apart.
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
                            Text("Wk").font(style.font(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
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
                                    .accessibilityLabel("Calendar Week \(numbers[week])")
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

/// Rings for CPU, RAM, storage (Caelestia: CircularProgress, stroke 6) -
/// stacked in the narrow card, side by side in the top row.
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
        if options.showMemory { Ring(value: model.memory, symbol: "memorychip", iconID: "panel-memory", help: String(localized: "Memory")) }
        if options.showStorage { Ring(value: model.storage, symbol: "internaldrive", iconID: "panel-disk", help: String(localized: "Storage")) }
    }
}

private struct Ring: View {
    let value: Double
    let symbol: String
    /// Identifier for the symbol replacement in the theme.
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
        .help("\(help) \(Int((value * 100).rounded()))%")
        .accessibilityLabel("\(help) \(Int((value * 100).rounded())) percent")
    }
}

/// About 24 SF Symbols to choose from for a page (context menu "Icon"
/// above) - enough variety without the menu overhead of a full symbol
/// picker. Until task 7 the same list lived in Nexus's old page builder
/// (`NexusDashboardPages.swift`, since removed).
let nexusPageSymbols = [
    "square.grid.2x2", "star", "house", "briefcase", "bolt", "gamecontroller",
    "moon.stars", "sun.max", "cloud.sun", "music.note", "film", "book",
    "paintbrush", "hammer", "wrench.and.screwdriver", "leaf", "pawprint",
    "airplane", "car", "bicycle", "figure.walk", "heart", "flag", "globe",
]
