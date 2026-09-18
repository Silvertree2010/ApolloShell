import ApolloShellCore
import SwiftUI

// Nexus > Dashboard, Bearbeiten > "Optionen" (design/2026-09-18-bento-plan-
// edit.md Task 4, rechte Spalte): die Einstellungen des gewaehlten Widgets -
// dieselben Schalter wie vor 0.2s Karten-Editor (NexusDashboardCardOptions,
// jetzt geloescht), gebunden an `editor.setOptions` statt an eine Karte.
// Neu: Zeitzone je Uhr, Orte je Wetter-Widget (`NexusWeatherModel`, eigener
// Sink statt weather.json).

/// Abschnitt "Optionen": das gewaehlte Widget, sonst ein Hinweis.
struct NexusDashboardOptionsSection: View {
    @Bindable var editor: DashboardEditor
    let weatherFile: URL?

    var body: some View {
        Section {
            if let id = editor.selectedWidgetID, let widget = editor.page?.widgets.first(where: { $0.id == id }) {
                NexusWidgetOptionsForm(editor: editor, widget: widget, weatherFile: weatherFile)
                    .id(widget.id)
            } else {
                Text("Ein Widget im Dashboard anklicken.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Optionen")
        }
    }
}

private struct NexusWidgetOptionsForm: View {
    @Bindable var editor: DashboardEditor
    let widget: WidgetInstance
    let weatherFile: URL?
    @State private var showsTimeZonePicker = false

    var body: some View {
        switch widget.kind {
        case .weather:
            let o = binding(\.weather, fallback: DashboardWeatherOptions())
            NexusToggle(title: "Wetterlage", subtitle: "Zum Beispiel „Leicht bewölkt“", isOn: o.showCondition)
            NexusToggle(title: "Höchst- und Tiefstwert", subtitle: "Von heute", isOn: o.showRange)
            places
        case .weatherHero, .weatherHourly, .weatherDaily:
            places
        case .user:
            let o = binding(\.user, fallback: DashboardUserOptions())
            NexusToggle(title: "macOS-Version", isOn: o.showSystem)
            NexusToggle(title: "Laufzeit", subtitle: "Wie lange der Mac seit dem Start läuft", isOn: o.showUptime)
        case .clock:
            let o = binding(\.clock, fallback: DashboardClockOptions())
            Picker("Darstellung", selection: o.style) {
                Text("Untereinander").tag(DashboardClockOptions.Style.stacked)
                Text("In einer Zeile").tag(DashboardClockOptions.Style.inline)
            }
            .pickerStyle(.segmented)
            NexusToggle(title: "Datum", subtitle: "Wochentag und Tag unter der Uhrzeit", isOn: o.showDate)
            LabeledContent("Zeitzone") {
                Button(NexusTimeZoneText.label(o.wrappedValue.timeZone)) { showsTimeZonePicker = true }
                    .popover(isPresented: $showsTimeZonePicker) {
                        NexusTimeZonePicker(selection: Binding(
                            get: { o.wrappedValue.timeZone },
                            set: { var value = o.wrappedValue; value.timeZone = $0; o.wrappedValue = value; showsTimeZonePicker = false }
                        ))
                    }
            }
        case .calendar:
            let o = binding(\.calendar, fallback: DashboardCalendarOptions())
            Picker("Woche beginnt am", selection: o.firstWeekday) {
                Text("Montag").tag(DashboardCalendarOptions.FirstWeekday.monday)
                Text("Sonntag").tag(DashboardCalendarOptions.FirstWeekday.sunday)
            }
            .pickerStyle(.segmented)
            NexusToggle(title: "Kalenderwochen", subtitle: "Links neben jeder Zeile", isOn: o.showWeekNumbers)
        case .resources:
            let o = binding(\.resources, fallback: DashboardResourcesOptions())
            let current = o.wrappedValue
            let last = [current.showCPU, current.showMemory, current.showStorage].filter { $0 }.count == 1
            NexusToggle(title: "CPU", isOn: o.showCPU).disabled(last && current.showCPU)
            NexusToggle(title: "Arbeitsspeicher", isOn: o.showMemory).disabled(last && current.showMemory)
            NexusToggle(title: "Speicher", subtitle: "Belegter Platz auf dem Startvolume", isOn: o.showStorage)
                .disabled(last && current.showStorage)
        case .media:
            let o = binding(\.media, fallback: DashboardMediaOptions())
            NexusToggle(title: "Album", subtitle: "Nicht in der kleinen Karte", isOn: o.showAlbum)
            NexusToggle(title: "Quelle", subtitle: "Welche App spielt", isOn: o.showSource)
        case .performanceCPU, .performanceGPU, .performanceStorage, .performanceNetwork,
             .performanceMemory, .performanceBattery, .mediaPlayer:
            Text("Für dieses Widget gibt es keine Einstellungen.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var places: some View {
        NexusWidgetPlacesSection(editor: editor, widget: widget, weatherFile: weatherFile)
    }

    /// Bindung an ein Feld der Widget-Optionen: liest den aktuellen Stand,
    /// schreibt ueber `editor.setOptions` - andere Felder bleiben, wie sie
    /// sind (anders als vor 0.2, wo eine neue Karte die alte ganz ersetzte).
    private func binding<T: Sendable>(_ path: WritableKeyPath<WidgetOptions, T?>, fallback: T) -> Binding<T> {
        Binding(
            get: { widget.options[keyPath: path] ?? fallback },
            set: { newValue in
                var options = widget.options
                options[keyPath: path] = newValue
                editor.setOptions(options, for: widget.id)
            }
        )
    }
}

/// Orte eines Wetter-Widgets: dieselben Zeilen wie vor 0.2 (Favoriten, Ort
/// suchen), aber je Widget statt gemeinsam in weather.json - der Sink von
/// `NexusWeatherModel` schreibt in `widget.options.places`.
private struct NexusWidgetPlacesSection: View {
    let editor: DashboardEditor
    let widget: WidgetInstance
    let weatherFile: URL?
    @State private var model: NexusWeatherModel

    init(editor: DashboardEditor, widget: WidgetInstance, weatherFile: URL?) {
        self.editor = editor
        self.widget = widget
        self.weatherFile = weatherFile
        let id = widget.id
        _model = State(initialValue: NexusWeatherModel(
            read: { editor.page?.widgets.first(where: { $0.id == id })?.options.places ?? .empty },
            write: { new in
                guard var options = editor.page?.widgets.first(where: { $0.id == id })?.options else { return false }
                options.places = new
                editor.setOptions(options, for: id)
                return true
            }
        ))
    }

    var body: some View {
        Divider()
        Text("Orte")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        if model.favorites.locations.isEmpty {
            Text("Noch keine Favoriten – unten einen Ort suchen und hinzufügen.")
                .foregroundStyle(.secondary)
        }
        ForEach(model.favorites.locations) { place in
            NexusWeatherFavoriteRow(model: model, place: place)
        }
        NexusSearchField(prompt: "Ort suchen", text: Binding(get: { model.query }, set: { model.query = $0 }),
                        busy: model.state == .searching)
        ForEach(model.results) { place in
            NexusWeatherSearchRow(model: model, place: place)
        }
    }
}

enum NexusTimeZoneText {
    static func label(_ identifier: String?) -> String {
        guard let identifier else { return String(localized: "System") }
        return city(identifier)
    }

    static func city(_ identifier: String) -> String {
        let parts = identifier.split(separator: "/")
        guard let last = parts.last else { return identifier }
        let city = last.replacingOccurrences(of: "_", with: " ")
        guard parts.count > 1 else { return city }
        let region = parts[parts.count - 2].replacingOccurrences(of: "_", with: " ")
        return "\(city) (\(region))"
    }
}

/// "System" plus eine durchsuchbare Liste aller IANA-Zeitzonen, Stadtteil
/// zuerst (z. B. "Tokyo (Asia)").
private struct NexusTimeZonePicker: View {
    @Binding var selection: String?
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var identifiers: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.sorted { NexusTimeZoneText.city($0) < NexusTimeZoneText.city($1) }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return all }
        return all.filter { NexusTimeZoneText.city($0).localizedStandardContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            NexusSearchField(prompt: "Zeitzone suchen", text: $query, busy: false)
                .padding(8)
            Divider()
            List {
                Button {
                    selection = nil
                    dismiss()
                } label: {
                    row("System", checked: selection == nil)
                }
                ForEach(identifiers, id: \.self) { id in
                    Button {
                        selection = id
                        dismiss()
                    } label: {
                        row(NexusTimeZoneText.city(id), checked: selection == id)
                    }
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 260, height: 320)
    }

    private func row(_ title: String, checked: Bool) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            if checked { Image(systemName: "checkmark") }
        }
        .contentShape(.rect)
    }
}
