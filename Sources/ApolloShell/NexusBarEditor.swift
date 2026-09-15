import AppKit
import ApolloShellCore
import SwiftUI

// MARK: - Seite

/// Nexus > Leiste (Caelestia: Panels > Taskbar): die Leiste als Baukasten.
/// Links die Bausteine von oben nach unten - ziehen zum Umsortieren,
/// Optionen zum Aufklappen, "Hinzufuegen" mit Galerie, Vorlagen -, rechts die
/// echte Leiste (`SidebarContent`) mit Vorschau-Modellen, verkleinert. Jede
/// Aenderung gilt sofort in der Leiste und landet in settings.json.
struct NexusBarPage: View {
    @Bindable var store: ShellSettingsStore
    @State private var showsGallery = false
    @State private var pending: NexusBarReplacement?
    /// Aufgeklappte Zeilen nach Kennung: bleiben beim Umsortieren offen.
    @State private var expanded: Set<String> = []

    /// `expanded`: schon aufgeklappte Zeilen (Bildprobe).
    init(store: ShellSettingsStore, expanded: Set<String> = []) {
        _store = Bindable(store)
        _expanded = State(initialValue: expanded)
    }

    private var layout: BarLayout { store.settings.bar.layout }

    var body: some View {
        HStack(spacing: 0) {
            NexusPageForm(page: .bar) {
                entriesSection
                NexusSaveWarning(failed: store.saveFailed)
            }
            Divider()
            NexusBarPreview(store: store)
                .frame(width: 124)
        }
        .sheet(isPresented: $showsGallery) {
            NexusBarGallery(layout: layout, onAdd: add, onCancel: { showsGallery = false })
        }
        .alert(pending?.title ?? "", isPresented: confirming, presenting: pending) { replacement in
            Button(replacement.confirm) { apply(replacement) }
            Button("Abbrechen", role: .cancel) {}
        } message: { replacement in
            Text(replacement.message)
        }
    }

    private var entriesSection: some View {
        Section {
            if layout.entries.isEmpty {
                Text("Die Leiste ist leer. Mit „Hinzufügen“ Bausteine holen oder eine Vorlage laden.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(layout.entries.enumerated()), id: \.element.id) { index, entry in
                NexusBarRow(store: store, entry: entry, isFirst: index == 0,
                            isLast: index == layout.entries.count - 1, isExpanded: expandedBinding(entry.id))
            }
            .onMove { store.settings.bar.layout.move(fromOffsets: $0, toOffset: $1) }
            HStack(spacing: 8) {
                Button {
                    showsGallery = true
                } label: {
                    Label("Hinzufügen …", systemImage: "plus")
                }
                Spacer(minLength: 8)
                Menu("Vorlage laden …") {
                    ForEach(BarPreset.allCases) { preset in
                        Button(preset.title) { pending = .preset(preset) }
                    }
                }
                .fixedSize()
                Button("Zurücksetzen") { pending = .reset }
                    .disabled(layout == BarPreset.caelestia.layout)
            }
        } header: {
            Text("Bausteine")
        } footer: {
            Text("Von oben nach unten wie in der Leiste. Zum Umsortieren ziehen oder das Kontextmenü nehmen. Das Dock und flexible Abstände teilen sich den freien Platz.")
        }
    }

    private var confirming: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private func expandedBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(id) }, set: { open in
            if open { expanded.insert(id) } else { expanded.remove(id) }
        })
    }

    /// Aus der Galerie: an die uebliche Stelle, mit Optionen gleich
    /// aufgeklappt - beim App-Knopf muss man ja noch die App waehlen.
    private func add(_ kind: BarModuleKind) {
        showsGallery = false
        if let id = store.settings.bar.layout.add(kind), BarModule(kind).hasOptions {
            expanded.insert(id)
        }
    }

    private func apply(_ replacement: NexusBarReplacement) {
        store.settings.bar.layout = replacement.layout
        expanded = []
    }
}

/// Was nach Rueckfrage die ganze Leiste ersetzt.
private enum NexusBarReplacement {
    case preset(BarPreset)
    case reset

    var layout: BarLayout {
        switch self {
        case .preset(let preset): preset.layout
        case .reset: BarPreset.caelestia.layout
        }
    }

    var title: String {
        switch self {
        case .preset(let preset): String(localized: "Vorlage „\(preset.title)“ laden?")
        case .reset: String(localized: "Leiste zurücksetzen?")
        }
    }

    var message: String {
        switch self {
        case .preset(let preset): String(localized: "\(preset.summary) Die jetzige Anordnung wird ersetzt.")
        case .reset: String(localized: "Die Leiste sieht wieder aus wie am Anfang (Vorlage Caelestia). Die jetzige Anordnung wird ersetzt.")
        }
    }

    var confirm: String {
        switch self {
        case .preset: String(localized: "Laden")
        case .reset: String(localized: "Zurücksetzen")
        }
    }
}

// MARK: - Zeile

/// Kachel, Name, eine Zeile Zusammenfassung, Entfernen, Griff. Mit Optionen
/// als aufklappbare Gruppe. Kontextmenue "Nach oben/unten" fuer alle, die
/// nicht ziehen wollen oder koennen; dasselbe als Bedienungshilfen-Aktion.
private struct NexusBarRow: View {
    @Bindable var store: ShellSettingsStore
    let entry: BarEntry
    let isFirst: Bool
    let isLast: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        Group {
            if entry.module.hasOptions {
                DisclosureGroup(isExpanded: $isExpanded) {
                    NexusBarOptions(store: store, entry: entry)
                } label: {
                    label
                }
            } else {
                // So weit eingerueckt, wie die Gruppe fuer ihren Pfeil
                // einrueckt (Bildprobe 14.09., macOS 26: links 11,5 pt,
                // rechts 4 pt) - sonst stuenden Kacheln und Entfernen-Knoepfe
                // der Zeilen mit und ohne Optionen versetzt.
                label
                    .padding(.leading, 11.5)
                    .padding(.trailing, 4)
            }
        }
        .contextMenu {
            Button("Nach oben") { move(-1) }
                .disabled(isFirst)
            Button("Nach unten") { move(1) }
                .disabled(isLast)
            Divider()
            Button("Entfernen", role: .destructive) { remove() }
        }
        .accessibilityAction(named: "Nach oben") { move(-1) }
        .accessibilityAction(named: "Nach unten") { move(1) }
    }

    private var label: some View {
        HStack(spacing: 10) {
            NexusTile(symbol: entry.kind.symbol, tint: entry.kind.tint, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.kind.title)
                Text(NexusBarText.detail(entry.module))
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
            .accessibilityLabel("\(entry.kind.title) entfernen")
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }

    private func move(_ step: Int) {
        store.settings.bar.layout.move(id: entry.id, by: step)
    }

    private func remove() {
        store.settings.bar.layout.remove(id: entry.id)
    }
}

/// Die Optionen eines Bausteins. Jede Aenderung ersetzt die Optionen dieses
/// einen Eintrags (`BarLayout.update`) - die Art bleibt dabei dieselbe.
private struct NexusBarOptions: View {
    @Bindable var store: ShellSettingsStore
    let entry: BarEntry
    @State private var picksApp = false

    var body: some View {
        switch entry.module {
        case .workspaces:
            let options = binding(\.workspaces, BarModule.workspaces, fallback: BarWorkspacesOptions())
            Picker("Darstellung", selection: options.style) {
                Text("Punkte").tag(BarWorkspacesOptions.Style.dots)
                Text("Nummern").tag(BarWorkspacesOptions.Style.numbers)
            }
            .pickerStyle(.segmented)
        case .dock:
            let options = binding(\.dock, BarModule.dock, fallback: BarDockOptions())
            NexusToggle(title: "Laufende Apps zeigen", subtitle: "Auch nicht angeheftete, unter einem Strich",
                        isOn: options.showRunning)
            Picker("Symbolgrösse", selection: options.iconSize) {
                ForEach(BarDockOptions.IconSize.allCases, id: \.self) { size in
                    Text(NexusBarText.size(size)).tag(size)
                }
            }
            .pickerStyle(.segmented)
        case .clock:
            let options = binding(\.clock, BarModule.clock, fallback: BarClockOptions())
            NexusToggle(title: "Symbol zeigen", subtitle: "Kalendersymbol über der Uhrzeit", isOn: options.showIcon)
            NexusToggle(title: "Datum zeigen", subtitle: "Wochentag und Tag über der Uhrzeit", isOn: options.showDate)
        case .statusIcons:
            let options = binding(\.statusIcons, BarModule.statusIcons, fallback: BarStatusIconsOptions())
            NexusToggle(title: "WLAN", isOn: options.showWifi)
            NexusToggle(title: "Bluetooth", isOn: options.showBluetooth)
            NexusToggle(title: "Akku", subtitle: "Nur auf Macs mit Akku", isOn: options.showBattery)
        case .gap:
            let options = binding(\.gap, BarModule.gap, fallback: BarGapOptions())
            // Stepper statt Schieber: jeder Schritt schreibt settings.json,
            // ein Schieber taete das bei jeder Mausbewegung.
            Stepper(value: options.height, in: BarGapOptions.range, step: 4) {
                LabeledContent("Höhe", value: "\(Int(options.wrappedValue.height)) pt")
            }
        case .appButton(let app):
            HStack(spacing: 10) {
                if let info = BarApps.info(for: app.bundleID) {
                    Image(nsImage: info.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 24, height: 24)
                    Text(info.name)
                } else {
                    Text(app.bundleID.isEmpty ? String(localized: "Noch keine App gewählt")
                         : String(localized: "\(app.bundleID) ist nicht installiert"))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("App wählen …") { picksApp = true }
            }
            .sheet(isPresented: $picksApp) {
                NexusBarAppPicker(current: app.bundleID, onPick: { id in
                    store.settings.bar.layout.update(id: entry.id, to: .appButton(.init(bundleID: id)))
                    picksApp = false
                }, onCancel: { picksApp = false })
            }
        case .battery:
            let options = binding(\.battery, BarModule.battery, fallback: BarBatteryOptions())
            NexusToggle(title: "Symbol zeigen", subtitle: "Akkusymbol über der Prozentzahl", isOn: options.showIcon)
        case .cpu:
            let options = binding(\.cpu, BarModule.cpu, fallback: BarCPUOptions())
            Picker("Darstellung", selection: options.style) {
                Text("Ring").tag(BarCPUOptions.Style.ring)
                Text("Prozent").tag(BarCPUOptions.Style.percent)
            }
            .pickerStyle(.segmented)
        case .weather:
            let options = binding(\.weather, BarModule.weather, fallback: BarWeatherOptions())
            NexusToggle(title: "Temperatur zeigen", subtitle: "Den Ort wählt man auf der Seite Dashboard",
                        isOn: options.showTemperature)
        case .dashboardButton, .utilitiesButton, .power, .spacer, .divider, .mediaButton:
            EmptyView()
        }
    }

    /// Bindung an die Optionen dieses Eintrags: lesen ueber den Zugriff der
    /// Art (`\.clock`), schreiben als neuer Baustein derselben Art.
    private func binding<T: Sendable>(
        _ read: @escaping @Sendable (BarModule) -> T?,
        _ make: @escaping @Sendable (T) -> BarModule,
        fallback: T
    ) -> Binding<T> {
        let id = entry.id
        let store = store
        return Binding(
            get: { store.settings.bar.layout[id: id].flatMap { read($0.module) } ?? fallback },
            set: { store.settings.bar.layout.update(id: id, to: make($0)) }
        )
    }
}

/// Unterzeilen der Liste: was der Baustein gerade zeigt.
@MainActor
enum NexusBarText {
    static func detail(_ module: BarModule) -> String {
        switch module {
        case .workspaces(let o):
            o.style == .dots ? String(localized: "Punkte") : String(localized: "Nummern")
        case .dock(let o):
            (o.showRunning ? String(localized: "Angeheftete und laufende Apps") : String(localized: "Nur angeheftete Apps"))
                + " · " + size(o.iconSize)
        case .clock(let o):
            ([String(localized: "Uhrzeit")] + (o.showIcon ? [String(localized: "Symbol")] : [])
                + (o.showDate ? [String(localized: "Datum")] : [])).joined(separator: " · ")
        case .statusIcons(let o):
            statusDetail(o)
        case .gap(let o):
            "\(Int(o.height)) pt"
        case .appButton(let o):
            BarApps.info(for: o.bundleID)?.name
                ?? (o.bundleID.isEmpty ? String(localized: "Noch keine App gewählt") : String(localized: "Nicht installiert"))
        case .battery(let o):
            o.showIcon ? String(localized: "Symbol und Prozent") : String(localized: "Nur Prozent")
        case .cpu(let o):
            o.style == .ring ? String(localized: "Ring mit Zahl") : String(localized: "Symbol und Prozent")
        case .weather(let o):
            o.showTemperature ? String(localized: "Symbol und Temperatur") : String(localized: "Nur Symbol")
        case .dashboardButton, .utilitiesButton, .power, .spacer, .divider, .mediaButton:
            module.kind.summary
        }
    }

    static func size(_ size: BarDockOptions.IconSize) -> String {
        switch size {
        case .small: String(localized: "Klein")
        case .medium: String(localized: "Mittel")
        case .large: String(localized: "Gross")
        }
    }

    private static func statusDetail(_ o: BarStatusIconsOptions) -> String {
        let parts = [o.showWifi ? String(localized: "WLAN") : nil, o.showBluetooth ? String(localized: "Bluetooth") : nil,
                     o.showBattery ? String(localized: "Akku") : nil]
            .compactMap { $0 }
        return parts.isEmpty ? String(localized: "Keines gewählt – unsichtbar") : parts.joined(separator: " · ")
    }
}

// MARK: - Galerie

/// Hinter "Hinzufuegen": jede Art mit Symbol, Name und einer Zeile. Ein
/// Klick fuegt sie ein; was es nur einmal gibt und schon da ist, bleibt grau.
struct NexusBarGallery: View {
    let layout: BarLayout
    let onAdd: (BarModuleKind) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Baustein hinzufügen")
                    .font(.title3.weight(.semibold))
                Text("Er kommt unter das Dock bzw. den letzten flexiblen Abstand – danach an die richtige Stelle ziehen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(BarModuleKind.allCases) { kind in
                        NexusBarGalleryTile(kind: kind, available: layout.canAdd(kind)) { onAdd(kind) }
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
        .frame(width: 560, height: 520)
    }
}

private struct NexusBarGalleryTile: View {
    let kind: BarModuleKind
    let available: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    NexusTile(symbol: kind.symbol, tint: kind.tint, size: 30)
                    Spacer(minLength: 4)
                    if !available {
                        Text("Schon da")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
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
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(Color.primary.opacity(hovering && available ? 0.09 : 0.05),
                        in: .rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.45)
        // Nexus ist ein normales, aktives Fenster: hier reicht onHover.
        .onHover { hovering = $0 }
        .help(available ? "\(kind.title) hinzufügen" : "Gibt es nur einmal und steht schon in der Leiste")
    }
}

// MARK: - App waehlen

/// Installierte Apps mit Suche (unscharf wie im Launcher). Gelesen beim
/// Oeffnen, wie der Launcher es bei jedem Oeffnen tut (einige ms).
struct NexusBarAppPicker: View {
    let current: String
    let onPick: (String) -> Void
    let onCancel: () -> Void
    @State private var query = ""
    @State private var apps: [AppEntry]

    /// `apps` vorgegeben (Bildprobe): kein Einlesen.
    init(current: String, apps: [AppEntry] = [], onPick: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.current = current
        self.onPick = onPick
        self.onCancel = onCancel
        _apps = State(initialValue: apps)
    }

    private var results: [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        let matcher = FuzzyMatcher()
        var scored: [(app: AppEntry, score: Int)] = []
        for app in apps {
            if let score = matcher.score(q, in: app.name) { scored.append((app, score)) }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
        }
        return scored.map(\.app)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("App wählen")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 10)
            NexusSearchField(prompt: "App suchen", text: $query)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            Divider()
            List(results, id: \.url) { app in
                Button {
                    if let id = app.bundleID { onPick(id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 24, height: 24)
                        Text(app.name)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if app.bundleID == current {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Divider()
            HStack {
                Spacer()
                Button("Abbrechen", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
        }
        .frame(width: 380, height: 480)
        .task {
            guard apps.isEmpty else { return }
            apps = AppCatalog().scan()
                .filter { $0.bundleID != nil }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}

// MARK: - Vorschau

/// Die echte Leiste mit Vorschau-Modellen, so hoch wie die Leiste auf dem
/// Hauptbildschirm und auf die Hoehe der Seite verkleinert. Ohne Maus
/// (`barPreview`): ein Klick hier soll nichts ausloesen.
struct NexusBarPreview: View {
    let store: ShellSettingsStore
    var context = NexusBarPreviewModels.context
    var barHeight = NexusBarPreviewModels.barHeight

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, max(geometry.size.height - 62, 80) / barHeight)
            VStack(spacing: 8) {
                Text("Vorschau")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                SidebarContent(settings: store, context: context)
                    .environment(\.barPreview, true)
                    .frame(width: Sidebar.width, height: barHeight)
                    // Ersatz fuer das Glas: eine leicht abgesetzte Flaeche.
                    .background(Color.primary.opacity(0.07))
                    .clipShape(.rect(cornerRadius: 9 / scale, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9 / scale, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1 / scale)
                    }
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: Sidebar.width * scale, height: barHeight * scale, alignment: .top)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Vorschau der Leiste")
                Text("Beispieldaten")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 14)
        }
    }
}

/// Feste Modelle fuer die Vorschau: messen, rufen und starten nichts. Die
/// Apps im Dock sind mitgelieferte Apple-Apps (nur die vorhandenen), der
/// Akku ist der echte (einmal gelesen), damit ein Mac ohne Akku auch in der
/// Vorschau keinen zeigt.
@MainActor
enum NexusBarPreviewModels {
    /// Hauptbildschirm bis unter die Menueleiste, wie `Sidebar.layout`.
    static var barHeight: CGFloat {
        guard let screen = NSScreen.screens.first else { return 900 }
        return max(screen.visibleFrame.maxY - screen.frame.minY, 400)
    }

    static let context: BarModuleContext = {
        let now = Date()
        let report = WeatherReport(
            current: CurrentWeather(time: now, temperature: 18, apparentTemperature: nil, humidity: nil,
                                    code: 2, windSpeed: nil, isDay: true),
            hours: [], days: [], timeZone: .current
        )
        return BarModuleContext(
            status: StatusModel(previewWifiRSSI: -55, battery: StatusModel.readBattery(), bluetoothOn: true),
            spaces: SpacesModel(preview: SpaceSnapshot(desktops: [1, 2, 3], activeIndex: 0)),
            dock: SidebarDockModel(preview: dockEntries(), frontmost: "com.apple.Safari"),
            clock: SidebarClockModel(preview: now),
            cpu: BarCPUModel(preview: 0.18),
            weather: BarWeatherFeed(preview: WeatherModel.preview(report: report, fetchedAt: now, now: now))
        )
    }()

    private static func dockEntries() -> [SidebarDockModel.Entry] {
        let ids = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.Notes", "com.apple.iCal",
                   "com.apple.Music", "com.apple.systempreferences"]
        let running: Set<String> = ["com.apple.finder", "com.apple.Safari"]
        return ids.compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return SidebarDockModel.Entry(bundleID: id, name: FileManager.default.displayName(atPath: url.path),
                                          icon: NSWorkspace.shared.icon(forFile: url.path), pinned: true,
                                          running: running.contains(id))
        }
    }
}
