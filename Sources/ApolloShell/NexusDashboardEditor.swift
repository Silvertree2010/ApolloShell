import AppKit
import ApolloShellCore
import SwiftUI

// Nexus > Dashboard als Baukasten (Caelestia: Panels > Dashboard), nach dem
// Muster der Leiste (NexusBarEditor.swift): Listen zum Ziehen, Optionen zum
// Aufklappen, Galerie hinter "Hinzufuegen", Vorlagen mit Rueckfrage und die
// echte Ansicht als verkleinerte Vorschau. Jede Aenderung gilt sofort und
// landet in settings.json (Abschnitt "dashboard").
//
// Die Seite selbst (mit dem Wetterort) steht in NexusDashboardPage.swift.

// MARK: - Reiter

/// Alle vier Reiter mit Schalter; ziehen ordnet sie wie im Dashboard von
/// links nach rechts.
struct NexusDashboardTabsSection: View {
    @Bindable var store: ShellSettingsStore

    private var tabs: DashboardTabs { store.settings.dashboard.tabs }

    var body: some View {
        Section {
            ForEach(Array(tabs.order.enumerated()), id: \.element) { index, tab in
                NexusDashboardTabRow(store: store, tab: tab, isFirst: index == 0,
                                     isLast: index == tabs.order.count - 1)
            }
            .onMove { store.settings.dashboard.tabs.move(fromOffsets: $0, toOffset: $1) }
        } header: {
            Text("Reiter")
        } footer: {
            Text("Von oben nach unten wie im Dashboard von links nach rechts; zum Umsortieren ziehen. Einer bleibt immer sichtbar. Will die Leiste einen ausgeblendeten Reiter öffnen, zeigt das Dashboard den ersten sichtbaren.")
        }
    }
}

private struct NexusDashboardTabRow: View {
    @Bindable var store: ShellSettingsStore
    let tab: DashboardTab
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        let tabs = store.settings.dashboard.tabs
        let visible = tabs.isVisible(tab)
        // Der letzte sichtbare: Schalter gesperrt statt ein Klick, der nichts tut.
        let locked = visible && !tabs.canHide(tab)
        HStack(spacing: 10) {
            NexusTile(symbol: tab.symbol, tint: tab.tint, size: 24)
                .opacity(visible ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title)
                Text(locked ? "Der letzte sichtbare Reiter bleibt" : NexusDashboardText.detail(tab))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle("\(tab.title) zeigen", isOn: Binding(
                get: { store.settings.dashboard.tabs.isVisible(tab) },
                set: { store.settings.dashboard.tabs.setVisible(tab, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(locked)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .contextMenu {
            Button("Nach links") { move(-1) }
                .disabled(isFirst)
            Button("Nach rechts") { move(1) }
                .disabled(isLast)
        }
        .accessibilityAction(named: "Nach links") { move(-1) }
        .accessibilityAction(named: "Nach rechts") { move(1) }
    }

    private func move(_ step: Int) {
        store.settings.dashboard.tabs.move(tab, by: step)
    }
}

// MARK: - Karten

/// Je Platz eine Gruppe (obere Reihe, untere Reihe, Seitenspalte), darunter
/// Hinzufuegen, Vorlagen und Zuruecksetzen. Ziehen ordnet innerhalb eines
/// Platzes; in einen anderen geht es ueber "Platz" in den Optionen oder das
/// Kontextmenue - SwiftUIs Ziehen kennt keine Wechsel zwischen Gruppen.
struct NexusDashboardCardSections: View {
    @Bindable var store: ShellSettingsStore
    @Binding var expanded: Set<DashboardCardKind>
    let onAdd: () -> Void
    let onReplace: (NexusDashboardReplacement) -> Void

    private var layout: DashboardLayout { store.settings.dashboard }

    var body: some View {
        ForEach(DashboardZone.allCases) { zone in
            Section {
                if zone == .top && !layout.tabs.isVisible(.dashboard) {
                    Label("Der Reiter Dashboard ist ausgeblendet. Die Karten erscheinen erst, wenn er wieder sichtbar ist.",
                          systemImage: "eye.slash")
                        .foregroundStyle(.secondary)
                }
                let list = layout.cards[zone]
                if list.isEmpty {
                    Text(NexusDashboardText.empty(zone))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(list.enumerated()), id: \.element.kind) { index, card in
                    NexusDashboardCardRow(store: store, card: card, zone: zone, isFirst: index == 0,
                                          isLast: index == list.count - 1, isExpanded: expandedBinding(card.kind))
                }
                .onMove { store.settings.dashboard.cards.move(in: zone, fromOffsets: $0, toOffset: $1) }
            } header: {
                Text(zone.title)
            } footer: {
                Text(NexusDashboardText.footer(zone))
            }
        }
        Section {
            HStack(spacing: 8) {
                Button(action: onAdd) {
                    Label("Hinzufügen …", systemImage: "plus")
                }
                Spacer(minLength: 8)
                Menu("Vorlage laden …") {
                    ForEach(DashboardPreset.allCases) { preset in
                        Button(preset.title) { onReplace(.preset(preset)) }
                    }
                }
                .fixedSize()
                Button("Zurücksetzen") { onReplace(.reset) }
                    .disabled(layout == DashboardLayout())
            }
        } footer: {
            Text("Das Dashboard bleibt immer gleich gross. Fehlt eine Karte, nehmen ihre Nachbarn den Platz ein; eine leere Reihe überlässt der anderen die ganze Höhe.")
        }
    }

    private func expandedBinding(_ kind: DashboardCardKind) -> Binding<Bool> {
        Binding(get: { expanded.contains(kind) }, set: { open in
            if open { expanded.insert(kind) } else { expanded.remove(kind) }
        })
    }
}

/// Kachel, Name, eine Zeile Zusammenfassung, Entfernen, Griff; Optionen zum
/// Aufklappen. Kontextmenue: nach links/rechts, an einen anderen Platz,
/// tauschen, entfernen - auch als Bedienungshilfen-Aktionen.
private struct NexusDashboardCardRow: View {
    @Bindable var store: ShellSettingsStore
    let card: DashboardCard
    let zone: DashboardZone
    let isFirst: Bool
    let isLast: Bool
    @Binding var isExpanded: Bool

    private var cards: DashboardCards { store.settings.dashboard.cards }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            NexusDashboardCardOptions(store: store, card: card, zone: zone)
        } label: {
            label
        }
        .contextMenu {
            if zone.isRow {
                Button("Nach links") { step(-1) }
                    .disabled(isFirst)
                Button("Nach rechts") { step(1) }
                    .disabled(isLast)
            }
            Menu("Verschieben nach") {
                ForEach(card.kind.zones.filter { $0 != zone }) { target in
                    Button(target.title) { store.settings.dashboard.cards.move(card.kind, to: target) }
                        .disabled(!cards.canMove(card.kind, to: target))
                }
            }
            .disabled(card.kind.zones.count < 2)
            Menu("Tauschen mit") {
                ForEach(cards.all.filter { $0.kind != card.kind }) { other in
                    Button(other.kind.title) { store.settings.dashboard.cards.swap(card.kind, other.kind) }
                        .disabled(!cards.canSwap(card.kind, other.kind))
                }
            }
            Divider()
            Button("Entfernen", role: .destructive) { remove() }
        }
        .accessibilityAction(named: "Nach links") { step(-1) }
        .accessibilityAction(named: "Nach rechts") { step(1) }
    }

    private var label: some View {
        HStack(spacing: 10) {
            NexusTile(symbol: card.kind.symbol, tint: card.kind.tint, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(card.kind.title)
                Text(NexusDashboardText.detail(card, zone: zone))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Entfernen")
            .accessibilityLabel("\(card.kind.title) entfernen")
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }

    private func step(_ step: Int) {
        store.settings.dashboard.cards.move(card.kind, by: step)
    }

    private func remove() {
        store.settings.dashboard.cards.remove(card.kind)
    }
}

/// Die Optionen einer Karte und ihr Platz. Jede Aenderung ersetzt die
/// Optionen genau dieser Karte (`DashboardCards.update`); die Breite haengt
/// nie an den Optionen, deshalb passt die Reihe danach immer noch.
private struct NexusDashboardCardOptions: View {
    @Bindable var store: ShellSettingsStore
    let card: DashboardCard
    let zone: DashboardZone

    var body: some View {
        switch card {
        case .weather:
            let o = binding(\.weather, DashboardCard.weather, fallback: DashboardWeatherOptions())
            NexusToggle(title: "Wetterlage", subtitle: "Zum Beispiel „Leicht bewölkt“", isOn: o.showCondition)
            NexusToggle(title: "Höchst- und Tiefstwert", subtitle: "Von heute", isOn: o.showRange)
        case .user:
            let o = binding(\.user, DashboardCard.user, fallback: DashboardUserOptions())
            NexusToggle(title: "macOS-Version", isOn: o.showSystem)
            NexusToggle(title: "Laufzeit", subtitle: "Wie lange der Mac seit dem Start läuft", isOn: o.showUptime)
        case .clock:
            let o = binding(\.clock, DashboardCard.clock, fallback: DashboardClockOptions())
            Picker("Darstellung", selection: o.style) {
                Text("Untereinander").tag(DashboardClockOptions.Style.stacked)
                Text("In einer Zeile").tag(DashboardClockOptions.Style.inline)
            }
            .pickerStyle(.segmented)
            NexusToggle(title: "Datum", subtitle: "Wochentag und Tag unter der Uhrzeit", isOn: o.showDate)
        case .calendar:
            let o = binding(\.calendar, DashboardCard.calendar, fallback: DashboardCalendarOptions())
            Picker("Woche beginnt am", selection: o.firstWeekday) {
                Text("Montag").tag(DashboardCalendarOptions.FirstWeekday.monday)
                Text("Sonntag").tag(DashboardCalendarOptions.FirstWeekday.sunday)
            }
            .pickerStyle(.segmented)
            NexusToggle(title: "Kalenderwochen", subtitle: "Links neben jeder Zeile", isOn: o.showWeekNumbers)
        case .resources(let current):
            let o = binding(\.resources, DashboardCard.resources, fallback: DashboardResourcesOptions())
            // Der letzte Ring bleibt: eine leere Karte ergaebe keinen Sinn.
            let last = current.count == 1
            NexusToggle(title: "CPU", isOn: o.showCPU)
                .disabled(last && current.showCPU)
            NexusToggle(title: "Arbeitsspeicher", isOn: o.showMemory)
                .disabled(last && current.showMemory)
            NexusToggle(title: "Speicher", subtitle: "Belegter Platz auf dem Startvolume", isOn: o.showStorage)
                .disabled(last && current.showStorage)
        case .media:
            let o = binding(\.media, DashboardCard.media, fallback: DashboardMediaOptions())
            NexusToggle(title: "Album", subtitle: "Nicht in der kleinen Karte der unteren Reihe", isOn: o.showAlbum)
            NexusToggle(title: "Quelle", subtitle: "Welche App spielt; nur in der Seitenspalte", isOn: o.showSource)
        }
        place
    }

    /// Wohin die Karte darf; was nicht passt, bleibt grau. Die belegte
    /// Spalte ist kein Hindernis: dann tauschen die beiden.
    @ViewBuilder private var place: some View {
        let cards = store.settings.dashboard.cards
        if card.kind.zones.count > 1 {
            LabeledContent("Platz") {
                Menu(zone.title) {
                    ForEach(card.kind.zones) { target in
                        Button {
                            store.settings.dashboard.cards.move(card.kind, to: target)
                        } label: {
                            if target == zone {
                                Label(target.title, systemImage: "checkmark")
                            } else {
                                Text(target.title)
                            }
                        }
                        .disabled(target != zone && !cards.canMove(card.kind, to: target))
                    }
                }
                .fixedSize()
            }
        } else {
            LabeledContent("Platz", value: "\(zone.title) – nur dort ist er hoch genug")
        }
    }

    /// Bindung an die Optionen dieser Karte: lesen ueber den Zugriff der Art
    /// (`\.clock`), schreiben als neue Karte derselben Art.
    private func binding<T: Sendable>(
        _ read: @escaping @Sendable (DashboardCard) -> T?,
        _ make: @escaping @Sendable (T) -> DashboardCard,
        fallback: T
    ) -> Binding<T> {
        let kind = card.kind
        let store = store
        return Binding(
            get: { store.settings.dashboard.cards[kind: kind].flatMap(read) ?? fallback },
            set: { store.settings.dashboard.cards.update(make($0)) }
        )
    }
}

/// Was nach Rueckfrage das ganze Dashboard ersetzt (Reiter und Karten).
enum NexusDashboardReplacement {
    case preset(DashboardPreset)
    case reset

    var layout: DashboardLayout {
        switch self {
        case .preset(let preset): preset.layout
        case .reset: DashboardLayout()
        }
    }

    var title: String {
        switch self {
        case .preset(let preset): String(localized: "Vorlage „\(preset.title)“ laden?")
        case .reset: String(localized: "Dashboard zurücksetzen?")
        }
    }

    var message: String {
        switch self {
        case .preset(let preset): String(localized: "\(preset.summary) Reiter und Karten werden ersetzt; der Wetterort bleibt.")
        case .reset: String(localized: "Reiter und Karten wieder wie am Anfang (Vorlage Caelestia). Der Wetterort bleibt.")
        }
    }

    var confirm: String {
        switch self {
        case .preset: String(localized: "Laden")
        case .reset: String(localized: "Zurücksetzen")
        }
    }
}

// MARK: - Galerie

/// Hinter "Hinzufuegen": jede Karte mit Symbol, Name und einer Zeile. Ein
/// Klick fuegt sie ein; was schon da ist oder nirgends Raum hat, bleibt grau.
struct NexusDashboardGallery: View {
    let cards: DashboardCards
    let onAdd: (DashboardCardKind) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Karte hinzufügen")
                    .font(.title3.weight(.semibold))
                Text("Sie kommt an ihren Platz wie bei Caelestia oder, wenn der voll ist, an den nächsten mit Raum.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(DashboardCardKind.allCases) { kind in
                        NexusDashboardGalleryTile(kind: kind, present: cards.contains(kind),
                                                  target: cards.placement(for: kind)) { onAdd(kind) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            Divider()
            HStack {
                Spacer()
                Button("Abbrechen", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
        }
        .frame(width: 560, height: 440)
    }
}

private struct NexusDashboardGalleryTile: View {
    let kind: DashboardCardKind
    let present: Bool
    /// Wohin sie kaeme; `nil` = schon da oder kein Raum.
    let target: DashboardZone?
    let action: () -> Void
    @State private var hovering = false

    private var available: Bool { target != nil }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    NexusTile(symbol: kind.symbol, tint: kind.tint, size: 30)
                    Spacer(minLength: 4)
                    Text(present ? String(localized: "Schon da") : target?.title ?? String(localized: "Kein Platz frei"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(kind.title)
                    .font(.headline)
                Text(kind.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(Color.primary.opacity(hovering && available ? 0.09 : 0.05),
                        in: .rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.45)
        .onHover { hovering = $0 }
        .help(present ? "Jede Karte gibt es einmal" : available ? "\(kind.title) hinzufügen"
              : "Kein Platz hat mehr Raum dafür – erst eine andere Karte entfernen")
    }
}

// MARK: - Vorschau

/// Das echte Dashboard mit Vorschau-Modellen, verkleinert. Unten fest statt
/// rechts wie bei der Leiste: das Dashboard ist breit, nicht hoch - daneben
/// waere es winzig. Ohne Maus: ein Klick hier soll nichts ausloesen.
struct NexusDashboardPreview: View {
    let store: ShellSettingsStore

    /// Hoehe des Streifens: ein gutes Drittel der Seite, in Grenzen.
    static func height(for page: CGFloat) -> CGFloat {
        min(max(page * 0.36, 170), 300)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = NexusDashboardPreviewModels.size
            let scale = min(1, (geometry.size.width - 40) / size.width, (geometry.size.height - 34) / size.height)
            VStack(spacing: 6) {
                DashboardView(model: NexusDashboardPreviewModels.dashboard, weather: NexusDashboardPreviewModels.weather,
                              media: NexusDashboardPreviewModels.media, settings: store)
                    // Ersatz fuer das Glas: eine leicht abgesetzte Flaeche.
                    .background(Color.primary.opacity(0.07))
                    .clipShape(.rect(cornerRadius: 25, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1 / max(scale, 0.1))
                    }
                    .scaleEffect(max(scale, 0.1), anchor: .top)
                    .frame(width: size.width * scale, height: size.height * scale, alignment: .top)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Vorschau des Dashboards")
                Text("Vorschau mit Beispieldaten")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        model: dashboard, weather: weather, media: media, settings: .preview()
    ).shellTheme()).fittingSize
}

// MARK: - Texte und Farben

@MainActor
enum NexusDashboardText {
    static func detail(_ tab: DashboardTab) -> String {
        switch tab {
        case .dashboard: String(localized: "Die Karten, die hier darunter stehen")
        case .media: String(localized: "Cover, Titel, Zeit und die spielende App")
        case .performance: String(localized: "CPU, GPU, Speicher, Netzwerk und Akku")
        case .weather: String(localized: "Jetzt, die nächsten Stunden und sieben Tage")
        }
    }

    /// Unterzeile einer Karte: was sie gerade zeigt.
    static func detail(_ card: DashboardCard, zone: DashboardZone) -> String {
        let parts: [String?] = switch card {
        case .weather(let o):
            [String(localized: "Temperatur"), o.showCondition ? String(localized: "Wetterlage") : nil,
             o.showRange ? String(localized: "Höchst/Tiefst") : nil]
        case .user(let o):
            [String(localized: "Name"), o.showSystem ? String(localized: "macOS") : nil,
             o.showUptime ? String(localized: "Laufzeit") : nil]
        case .clock(let o):
            [o.style == .stacked ? String(localized: "Untereinander") : String(localized: "In einer Zeile"),
             o.showDate ? String(localized: "Datum") : nil]
        case .calendar(let o):
            [o.firstWeekday == .monday ? String(localized: "Ab Montag") : String(localized: "Ab Sonntag"),
             o.showWeekNumbers ? String(localized: "Kalenderwochen") : nil]
        case .resources(let o):
            [o.showCPU ? String(localized: "CPU") : nil, o.showMemory ? String(localized: "RAM") : nil,
             o.showStorage ? String(localized: "Speicher") : nil]
        case .media(let o):
            switch zone {
            case .side:
                [String(localized: "Cover mit Fortschritt"), o.showAlbum ? String(localized: "Album") : nil,
                 o.showSource ? String(localized: "Quelle") : nil]
            case .top: [String(localized: "Als Streifen"), o.showAlbum ? String(localized: "Album") : nil]
            case .bottom: [String(localized: "Klein, hochkant")]
            }
        }
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    static func empty(_ zone: DashboardZone) -> String {
        switch zone {
        case .top, .bottom: String(localized: "Leer – die andere Reihe bekommt die ganze Höhe.")
        case .side: String(localized: "Leer – die Reihen gehen über die ganze Breite.")
        }
    }

    static func footer(_ zone: DashboardZone) -> String {
        switch zone {
        case .top: String(localized: "130 Punkte hoch. Karten mit fester Breite behalten sie, die übrigen teilen sich den Rest.")
        case .bottom: String(localized: "250 Punkte hoch. Nur hier ist Platz für den Kalender.")
        case .side: String(localized: "200 Punkte breit, eine Karte über die ganze Höhe. Ist sie belegt, tauscht eine neue mit ihr den Platz.")
        }
    }
}

/// Kachelfarben wie die Seitensymbole der Systemeinstellungen.
extension DashboardTab {
    var tint: Color {
        switch self {
        case .dashboard: .indigo
        case .media: .pink
        case .performance: .green
        case .weather: .cyan
        }
    }
}

extension DashboardCardKind {
    var tint: Color {
        switch self {
        case .weather: .cyan
        case .user: .blue
        case .clock: .orange
        case .calendar: .red
        case .resources: .green
        case .media: .pink
        }
    }
}
