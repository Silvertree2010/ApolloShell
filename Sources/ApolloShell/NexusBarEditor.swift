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
    /// Orte fuer den Wetter-Baustein der Leiste (weather.json) - seit dem
    /// globalen Bearbeitungsmodus hier statt auf einer eigenen Dashboard-
    /// Seite; sie sind zugleich die Vorgabe fuer neue Wetter-Widgets.
    var weather: NexusWeatherModel?
    @State private var showsGallery = false
    @State private var pending: LayoutPresetReplacement<BarPreset>?
    /// Aufgeklappte Zeilen nach Kennung: bleiben beim Umsortieren offen.
    @State private var expanded: Set<String> = []

    /// `expanded`: schon aufgeklappte Zeilen (Bildprobe).
    init(store: ShellSettingsStore, weather: NexusWeatherModel? = nil, expanded: Set<String> = []) {
        _store = Bindable(store)
        self.weather = weather
        _expanded = State(initialValue: expanded)
    }

    private var layout: BarLayout { store.settings.bar.layout }

    var body: some View {
        HStack(spacing: 0) {
            NexusPageForm(page: .bar) {
                entriesSection
                NexusBarScreensSection(store: store)
                NexusBarBackgroundSection(store: store)
                if let weather {
                    NexusDashboardWeatherSection(model: weather)
                    NexusSaveWarning(failed: weather.saveFailed, file: "weather.json")
                }
                NexusSaveWarning(failed: store.saveFailed)
            }
            Divider()
            NexusBarPreview(store: store)
                .frame(width: 124)
        }
        .sheet(isPresented: $showsGallery) {
            NexusBarGallery(layout: layout, onAdd: add, onCancel: { showsGallery = false })
        }
        .nexusPresetAlert($pending, title: NexusBarText.replacementTitle, message: NexusBarText.replacementMessage) { layout in
            store.settings.bar.layout = layout
            expanded = []
        }
    }

    private var entriesSection: some View {
        Section {
            if layout.entries.isEmpty {
                Text("The bar is empty. Use “Add” to get building blocks or load a preset.")
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
                    Label("Add…", systemImage: "plus")
                }
                Spacer(minLength: 8)
                NexusPresetMenu<BarPreset> { pending = .preset($0) }
                NexusPresetResetButton<BarPreset>(layout: layout) { pending = .reset }
            }
        } header: {
            Text("Building Blocks")
        } footer: {
            Text("Top to bottom as in the bar. Drag to reorder, or use the context menu. The Dock and flexible spacers share the free space.")
        }
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
}

// MARK: - Bildschirme

/// Nexus > Leiste > Bildschirme: auf welchen Bildschirmen die Leiste steht.
///
/// Ein einzelner Bildschirm wird ueber einen stabilen Schluessel gemerkt
/// (Name plus Aufloesung, siehe `ScreenInfo.key`) - eine Display-Kennung
/// vergibt macOS beim Anstecken neu und waere nach dem naechsten Mal ein
/// anderer Bildschirm. Ist der gemerkte nicht angeschlossen, steht die Leiste
/// auf dem Hauptbildschirm; in der Liste bleibt er trotzdem stehen, sonst
/// zeigte die Auswahl auf nichts und sie waere beim naechsten Anstecken weg.
private struct NexusBarScreensSection: View {
    @Bindable var store: ShellSettingsStore
    /// Angeschlossene Bildschirme, beim Erscheinen der Seite gelesen.
    @State private var screens: [ScreenInfo] = []

    var body: some View {
        Section {
            Picker("Screens", selection: $store.settings.bar.screens) {
                Text("All").tag(ScreenChoice.all)
                Text("Main Display Only").tag(ScreenChoice.primary)
                if !screens.isEmpty {
                    Divider()
                    ForEach(screens) { screen in
                        Text(screen.name).tag(ScreenChoice.single(screen.key))
                    }
                }
                if let missing {
                    Divider()
                    Text("\(missing) (not connected)").tag(ScreenChoice.single(missing))
                }
            }
        } header: {
            Text("Screens")
        } footer: {
            Text("Which screens the bar stands on – and with it the desktop clock and the strip the window guard keeps clear. A single screen is remembered by name and resolution; when it is not connected, the bar stands on the main display.")
        }
        .task { reload() }
    }

    /// Gleiche Schluessel zusammenfassen: zwei baugleiche Bildschirme sind
    /// fuer die Einstellung nicht zu unterscheiden (dann gilt der erste), und
    /// zwei Zeilen mit derselben Kennung braechten die Liste durcheinander.
    private func reload() {
        var seen: Set<String> = []
        screens = ShellScreens.current().map(\.info).filter { seen.insert($0.key).inserted }
    }

    /// Der gemerkte Bildschirm, wenn er gerade nicht angeschlossen ist.
    private var missing: String? {
        guard case .single(let key) = store.settings.bar.screens,
              !screens.contains(where: { $0.key == key })
        else { return nil }
        return key
    }
}

// MARK: - Hintergrund

/// Nexus > Leiste > Hintergrund: womit die Leiste und ihre Beule hinterlegt
/// sind.
///
/// Zur Wahl, weil Liquid Glass sich nach dem richtet, was dahinter liegt, und
/// sich nicht davon abbringen laesst - die Gruende und die Belege stehen bei
/// `BarBackground`. Die Eintraege unterscheiden sich sichtbar, damit man sie
/// am lebenden Schreibtisch vergleichen kann; Vorgabe bleibt Material.
private struct NexusBarBackgroundSection: View {
    @Bindable var store: ShellSettingsStore

    var body: some View {
        Section {
            ForEach(BarBackground.allCases) { background in
                NexusChoiceRow(selected: store.settings.bar.background == background) {
                    store.settings.bar.background = background
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        title(background)
                        subtitle(background)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Background")
        } footer: {
            Text("Liquid Glass follows the brightness of whatever is behind it, and it also flips between a light and a dark appearance – so the bar changes color as soon as a window moves underneath it. That cannot be switched off; for a fixed color, pick Material or glass on a solid fill.")
        }
    }

    private func title(_ background: BarBackground) -> Text {
        switch background {
        case .material: Text("Material")
        case .glass: Text("Liquid Glass")
        case .tintedGlass: Text("Liquid Glass, Tinted")
        case .fixedGlass: Text("Liquid Glass on a Solid Fill")
        }
    }

    private func subtitle(_ background: BarBackground) -> Text {
        switch background {
        case .material: Text("System material with a fixed color that follows light and dark – how it looks today")
        case .glass: Text("Real glass; it takes on the color and brightness of whatever is behind it")
        case .tintedGlass: Text("Glass tinted with the window color; it shifts less, but it still shifts")
        case .fixedGlass: Text("Clear glass over an opaque fill in the window color: the sheen stays, the color holds still")
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
            Button("Move Up") { move(-1) }
                .disabled(isFirst)
            Button("Move Down") { move(1) }
                .disabled(isLast)
            Divider()
            Button("Remove", role: .destructive) { remove() }
        }
        .accessibilityAction(named: "Move Up") { move(-1) }
        .accessibilityAction(named: "Move Down") { move(1) }
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
            .help("Remove")
            .accessibilityLabel("Remove \(entry.kind.title)")
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

    var body: some View {
        switch entry.module {
        case .workspaces:
            let options = binding(\.workspaces, BarModule.workspaces, fallback: BarWorkspacesOptions())
            Picker("Style", selection: options.style) {
                Text("Dots").tag(BarWorkspacesOptions.Style.dots)
                Text("Numbers").tag(BarWorkspacesOptions.Style.numbers)
            }
            .pickerStyle(.segmented)
        case .dock:
            let options = binding(\.dock, BarModule.dock, fallback: BarDockOptions())
            NexusToggle(title: "Show Running Apps", subtitle: "Also unpinned ones, below a divider",
                        isOn: options.showRunning)
            Picker("Icon Size", selection: options.iconSize) {
                ForEach(BarDockOptions.IconSize.allCases, id: \.self) { size in
                    Text(NexusBarText.size(size)).tag(size)
                }
            }
            .pickerStyle(.segmented)
        case .clock:
            let options = binding(\.clock, BarModule.clock, fallback: BarClockOptions())
            NexusToggle(title: "Show Icon", subtitle: "Calendar icon above the time", isOn: options.showIcon)
            NexusToggle(title: "Show Date", subtitle: "Weekday and day above the time", isOn: options.showDate)
        case .statusIcons:
            let options = binding(\.statusIcons, BarModule.statusIcons, fallback: BarStatusIconsOptions())
            NexusToggle(title: "Wi-Fi", isOn: options.showWifi)
            NexusToggle(title: "Bluetooth", isOn: options.showBluetooth)
            NexusToggle(title: "Battery", subtitle: "Only on Macs with a battery", isOn: options.showBattery)
        case .gap:
            let options = binding(\.gap, BarModule.gap, fallback: BarGapOptions())
            // Stepper statt Schieber: jeder Schritt schreibt settings.json,
            // ein Schieber taete das bei jeder Mausbewegung.
            Stepper(value: options.height, in: BarGapOptions.range, step: 4) {
                LabeledContent("Höhe", value: "\(Int(options.wrappedValue.height)) pt")
            }
        case .appButton(let app):
            NexusAppChoiceRow(bundleID: app.bundleID) { id in
                store.settings.bar.layout.update(id: entry.id, to: .appButton(.init(bundleID: id)))
            }
        case .battery:
            let options = binding(\.battery, BarModule.battery, fallback: BarBatteryOptions())
            NexusToggle(title: "Show Icon", subtitle: "Battery icon above the percentage", isOn: options.showIcon)
        case .cpu:
            let options = binding(\.cpu, BarModule.cpu, fallback: BarCPUOptions())
            Picker("Style", selection: options.style) {
                Text("Ring").tag(BarCPUOptions.Style.ring)
                Text("Percent").tag(BarCPUOptions.Style.percent)
            }
            .pickerStyle(.segmented)
        case .weather:
            let options = binding(\.weather, BarModule.weather, fallback: BarWeatherOptions())
            NexusToggle(title: "Show Temperature", subtitle: "The location is set on the Dashboard page",
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
        return nexusOptionsBinding(
            get: { store.settings.bar.layout[id: id]?.module },
            set: { store.settings.bar.layout.update(id: id, to: $0) },
            read: read, make: make, fallback: fallback
        )
    }
}

/// Unterzeilen der Liste: was der Baustein gerade zeigt.
@MainActor
enum NexusBarText {
    /// Titel der Vorlagen-Rueckfrage.
    static func replacementTitle(_ replacement: LayoutPresetReplacement<BarPreset>) -> String {
        switch replacement {
        case .preset(let preset): String(localized: "Load preset “\(preset.title)”?")
        case .reset: String(localized: "Reset the bar?")
        }
    }

    /// Erklaerung der Vorlagen-Rueckfrage.
    static func replacementMessage(_ replacement: LayoutPresetReplacement<BarPreset>) -> String {
        switch replacement {
        case .preset(let preset): String(localized: "\(preset.summary) The current arrangement will be replaced.")
        case .reset: String(localized: "The bar looks like it did at the start again (Caelestia preset). The current arrangement will be replaced.")
        }
    }

    static func detail(_ module: BarModule) -> String {
        switch module {
        case .workspaces(let o):
            o.style == .dots ? String(localized: "Dots") : String(localized: "Numbers")
        case .dock(let o):
            (o.showRunning ? String(localized: "Pinned and Running Apps") : String(localized: "Pinned Apps Only"))
                + " · " + size(o.iconSize)
        case .clock(let o):
            ([String(localized: "Time")] + (o.showIcon ? [String(localized: "Icon")] : [])
                + (o.showDate ? [String(localized: "Date")] : [])).joined(separator: " · ")
        case .statusIcons(let o):
            statusDetail(o)
        case .gap(let o):
            "\(Int(o.height)) pt"
        case .appButton(let o):
            BarApps.info(for: o.bundleID)?.name
                ?? (o.bundleID.isEmpty ? String(localized: "No App Chosen Yet") : String(localized: "Not Installed"))
        case .battery(let o):
            o.showIcon ? String(localized: "Icon and Percent") : String(localized: "Percent Only")
        case .cpu(let o):
            o.style == .ring ? String(localized: "Ring with Number") : String(localized: "Icon and Percent")
        case .weather(let o):
            o.showTemperature ? String(localized: "Icon and Temperature") : String(localized: "Icon Only")
        case .dashboardButton, .utilitiesButton, .power, .spacer, .divider, .mediaButton:
            module.kind.summary
        }
    }

    static func size(_ size: BarDockOptions.IconSize) -> String {
        switch size {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }

    private static func statusDetail(_ o: BarStatusIconsOptions) -> String {
        let parts = [o.showWifi ? String(localized: "Wi-Fi") : nil, o.showBluetooth ? String(localized: "Bluetooth") : nil,
                     o.showBattery ? String(localized: "Battery") : nil]
            .compactMap { $0 }
        return parts.isEmpty ? String(localized: "None chosen – invisible") : parts.joined(separator: " · ")
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
        NexusGallerySheet(title: String(localized: "Add Building Block"),
                          subtitle: String(localized: "It's added below the Dock, or after the last flexible spacer – drag it to the right place afterwards."),
                          size: CGSize(width: 560, height: 520), onCancel: onCancel) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(BarModuleKind.allCases) { kind in
                    let available = layout.canAdd(kind)
                    NexusGalleryTile(title: kind.title, summary: kind.summary,
                                     badge: available ? nil : String(localized: "Already Added"), minHeight: 118,
                                     available: available,
                                     help: available ? String(localized: "Add \(kind.title)")
                                         : String(localized: "Only exists once, and it's already in the bar"),
                                     action: { onAdd(kind) }) {
                        NexusTile(symbol: kind.symbol, tint: kind.tint, size: 30)
                    }
                }
            }
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
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                NexusScaledPreview(scale: scale, frameSize: CGSize(width: Sidebar.width * scale, height: barHeight * scale),
                                   cornerRadius: 9 / scale, accessibilityLabel: String(localized: "Preview of the Bar")) {
                    SidebarContent(settings: store, context: context)
                        .environment(\.barPreview, true)
                        .frame(width: Sidebar.width, height: barHeight)
                }
                Text("Sample Data")
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
