import ApolloShellCore
import SwiftUI

// Options of the selected widget in the popover next to it (Task 4,
// `BentoEditOverlay.swift`): the same switches as before 0.2's card editor
// (NexusDashboardCardOptions, deleted long ago) and, before Task 7, also Nexus'
// old 3-column kit (`NexusDashboardOptionsSection`, removed),
// bound to `editor.setOptions` instead of a card. New since 0.2: time zone
// per clock, places per weather widget (`NexusWeatherModel`, its own sink instead of
// weather.json).

struct WidgetOptionsView: View {
    @Bindable var editor: DashboardEditor
    let widget: WidgetInstance
    let weatherFile: URL?
    @State private var showsTimeZonePicker = false

    var body: some View {
        switch widget.kind {
        case .weather:
            let o = binding(\.weather, fallback: DashboardWeatherOptions())
            NexusToggle(title: "Condition", subtitle: "For example “Partly cloudy”", isOn: o.showCondition)
            NexusToggle(title: "High and Low", subtitle: "For today", isOn: o.showRange)
            places
        case .weatherHero, .weatherHourly, .weatherDaily:
            places
        case .user:
            let o = binding(\.user, fallback: DashboardUserOptions())
            NexusToggle(title: "macOS Version", isOn: o.showSystem)
            NexusToggle(title: "Uptime", subtitle: "How long the Mac has been running since starting up", isOn: o.showUptime)
        case .clock:
            let o = binding(\.clock, fallback: DashboardClockOptions())
            Picker("Style", selection: o.style) {
                Text("Stacked").tag(DashboardClockOptions.Style.stacked)
                Text("In One Row").tag(DashboardClockOptions.Style.inline)
            }
            .pickerStyle(.segmented)
            NexusToggle(title: "Date", subtitle: "Weekday and day below the time", isOn: o.showDate)
            LabeledContent("Time Zone") {
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
            Picker("Week Starts On", selection: o.firstWeekday) {
                Text("Monday").tag(DashboardCalendarOptions.FirstWeekday.monday)
                Text("Sunday").tag(DashboardCalendarOptions.FirstWeekday.sunday)
            }
            .pickerStyle(.segmented)
            NexusToggle(title: "Week Numbers", subtitle: "To the left of each row", isOn: o.showWeekNumbers)
        case .resources:
            let o = binding(\.resources, fallback: DashboardResourcesOptions())
            let current = o.wrappedValue
            let last = [current.showCPU, current.showMemory, current.showStorage].filter { $0 }.count == 1
            NexusToggle(title: "CPU", isOn: o.showCPU).disabled(last && current.showCPU)
            NexusToggle(title: "Memory", isOn: o.showMemory).disabled(last && current.showMemory)
            NexusToggle(title: "Storage", subtitle: "Space used on the startup volume", isOn: o.showStorage)
                .disabled(last && current.showStorage)
        case .media:
            let o = binding(\.media, fallback: DashboardMediaOptions())
            NexusToggle(title: "Album", subtitle: "Not shown in the small card", isOn: o.showAlbum)
            NexusToggle(title: "Source", subtitle: "Which app is playing", isOn: o.showSource)
        case .performanceCPU, .performanceGPU, .performanceStorage, .performanceNetwork,
             .performanceMemory, .performanceBattery, .mediaPlayer:
            Text("There are no settings for this widget.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var places: some View {
        NexusWidgetPlacesSection(editor: editor, widget: widget, weatherFile: weatherFile)
    }

    /// Binding to a field of the widget options: reads the current state,
    /// writes via `editor.setOptions` - other fields stay as they
    /// are (unlike before 0.2, where a new card replaced the old one entirely).
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

/// Places of a weather widget: the same rows as before 0.2 (favorites, search
/// for a place), but per widget instead of shared in weather.json - the sink of
/// `NexusWeatherModel` writes to `widget.options.places`.
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
        Text("Places")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        if model.favorites.locations.isEmpty {
            Text("No favorites yet – search for a place below and add it.")
                .foregroundStyle(.secondary)
        }
        ForEach(model.favorites.locations) { place in
            NexusWeatherFavoriteRow(model: model, place: place)
        }
        NexusSearchField(prompt: "Search for a Place", text: Binding(get: { model.query }, set: { model.query = $0 }),
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

/// "System" plus a searchable list of all IANA time zones, city
/// first (e.g. "Tokyo (Asia)").
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
            NexusSearchField(prompt: "Search Time Zone", text: $query, busy: false)
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
