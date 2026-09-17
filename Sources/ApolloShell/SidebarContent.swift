import AppKit
import ApolloShellCore
import SwiftUI

/// Inhalt der linken Leiste: die Bausteine aus Nexus > Leiste
/// (settings.bar.layout) von oben nach unten, jeder ueber `BarModuleView`.
///
/// Die Vorgabe (Vorlage "Caelestia") ist Caelestias Leiste (logo,
/// workspaces, spacer, activeWindow, spacer, tray, clock, statusIcons,
/// power): Dashboard, Spaces, Dock, Uhr, Utilities, Statuskapsel,
/// Ausschalten. Das Dock steht dort, wo bei Caelestia das aktive Fenster
/// steht; einen Tray gibt es nicht, an seiner Stelle sitzt Utilities.
///
/// Die Modelle der sieben alten Bausteine laufen immer (so ist ein wieder
/// hinzugefuegter sofort aktuell); CPU und Wetter messen nur, solange ihr
/// Baustein zu sehen ist.
struct SidebarContent: View {
    let settings: ShellSettingsStore
    let context: BarModuleContext

    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        let entries = settings.settings.bar.layout.entries
        // Mit Theme bestimmen `--apollo-bar-item-spacing` und
        // `--apollo-bar-padding` den Abstand der Bausteine und den Rand.
        BarStack(spacing: style.barItemSpacing(8)) {
            ForEach(entries) { entry in
                BarModuleView(entry: entry, context: context)
            }
        }
        // Oben und unten 10: vor dem Baukasten sass dieser Rand am
        // Dashboard- und am Ausschalt-Symbol - als Rand der Leiste gilt er
        // fuer jede Anordnung.
        .padding(.vertical, style.barPadding(10))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Umsortieren in Nexus gleitet sichtbar, statt zu springen.
        .animation(SidebarMotion.spatial, value: entries.map(\.id))
    }
}

/// Die Bausteine untereinander, 8 auseinander. Feste bekommen ihre Hoehe,
/// den Rest teilen sich die flexiblen (Dock, Abstand) zu gleichen Teilen -
/// Regeln und Tests in `BarFlex`. Eigenes Layout statt VStack: dort haengt
/// die Verteilung unter mehreren flexiblen von deren Mindest- und
/// Idealgroessen ab (ein Dock mit Scrollliste gegen einen leeren Abstand);
/// hier ist sie festgelegt. Mit genau einem flexiblen ist es dasselbe wie
/// der VStack vor dem Baukasten (Bildprobe: pixelgleich).
struct BarStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        if let height = proposal.height { return CGSize(width: width, height: height) }
        // Ideal: nur die festen, flexible zaehlen 0.
        let fixed = subviews.filter { !$0[BarFlexible.self] }
            .map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: fixed.reduce(0, +) + CGFloat(max(subviews.count - 1, 0)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let heights: [Double?] = subviews.map { subview in
            subview[BarFlexible.self]
                ? nil
                : Double(subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height)
        }
        let slots = BarFlex.slots(available: Double(bounds.height), heights: heights, spacing: Double(spacing))
        for (subview, slot) in zip(subviews, slots) {
            subview.place(at: CGPoint(x: bounds.midX, y: bounds.minY + slot.y), anchor: .top,
                          proposal: ProposedViewSize(width: bounds.width, height: slot.height))
        }
    }
}

/// Markiert einen Baustein als flexibel fuer `BarStack`.
struct BarFlexible: LayoutValueKey {
    static let defaultValue = false
}

/// Ein Baustein nach seiner Art - die eine Stelle, an der jede Art ihre
/// Ansicht bekommt. Eine neue Art braucht hier einen Fall (der Compiler
/// verlangt ihn), in ApolloShellCore ihre Optionen und in Nexus deren Editor.
///
/// Bausteine, die nichts zeigen koennen (Spaces ohne Schreibtisch-Liste,
/// Akku am Desktop-Mac), zeichnen nichts und bekommen dann auch keinen
/// Abstand - wie im VStack vorher.
struct BarModuleView: View {
    let entry: BarEntry
    let context: BarModuleContext

    var body: some View {
        switch entry.module {
        case .dashboardButton:
            SidebarIcon(help: String(localized: "Dashboard (SUPER+D)"), action: context.onDashboard) {
                ThemedIcon("bar-dashboard", fallback: "square.grid.2x2")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
        case .workspaces(let options):
            SidebarSpaces(model: context.spaces, style: options.style, onSelect: context.onSelectSpace)
        case .dock(let options):
            // Fuellt die Hoehe zwischen oberer und unterer Gruppe und steht
            // dort mittig - die zwei Spacer von Caelestia.
            SidebarDock(model: context.dock, options: options)
                .layoutValue(key: BarFlexible.self, value: true)
        case .clock(let options):
            SidebarClock(model: context.clock, showIcon: options.showIcon, showDate: options.showDate)
                // Klick oeffnet das Dashboard mit dem Kalender.
                .contentShape(.rect)
                .onTapGesture { context.onDashboard() }
        case .utilitiesButton:
            SidebarIcon(help: String(localized: "Utilities (SUPER+U)"), action: context.onUtilities) {
                // Mit `icons/bar-utilities.png` im Theme steht dort dieses Bild.
                ThemedIcon("bar-utilities")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
        case .statusIcons(let options):
            StatusCapsule(status: context.status, options: options)
        case .power:
            SidebarIcon(help: String(localized: "Sitzung"), action: context.onPower) {
                ThemedIcon("bar-power")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
        case .spacer:
            Color.clear
                .layoutValue(key: BarFlexible.self, value: true)
                .accessibilityHidden(true)
        case .gap(let options):
            Color.clear
                .frame(width: 1, height: options.height)
                .accessibilityHidden(true)
        case .divider:
            // Wie der Strich im Dock zwischen angehefteten und laufenden.
            Capsule()
                .fill(Color.primary.opacity(0.18))
                .frame(width: 20, height: 2)
                .accessibilityHidden(true)
        case .appButton(let options):
            BarAppButton(bundleID: options.bundleID, onOpen: context.onOpenApp)
        case .battery(let options):
            BarBatteryModule(status: context.status, options: options) { context.onDashboardTab(.performance) }
        case .cpu(let options):
            BarCPUModule(model: context.cpu, options: options) { context.onDashboardTab(.performance) }
        case .weather(let options):
            BarWeatherModule(feed: context.weather, options: options) { context.onDashboardTab(.weather) }
        case .mediaButton:
            SidebarIcon(help: String(localized: "Medien"), action: { context.onDashboardTab(.media) }) {
                Image(systemName: "music.note")
                    .font(.system(size: 15, weight: .semibold))
            }
        }
    }
}

/// Die Statussymbole untereinander in einer Kapsel mit leicht abgesetztem
/// Hintergrund (Caelestia: StatusIcons, radius "full"). Welche, bestimmt
/// Nexus; ist keins uebrig, faellt die Kapsel ganz weg.
/// Ein Klick oeffnet das Detailfenster daneben (`StatusPopout`); das
/// Symbol des offenen bleibt hinterlegt. Das Modell kommt aus der Umgebung -
/// fehlt es (Vorschau, Bildproben), sind die Symbole nur Anzeige.
private struct StatusCapsule: View {
    let status: StatusModel
    var options = BarStatusIconsOptions()
    @Environment(StatusPopoutModel.self) private var popout: StatusPopoutModel?

    var body: some View {
        let battery = options.showBattery ? StatusGlyphs.batterySymbol(status.battery) : nil
        if options.showWifi || options.showBluetooth || battery != nil {
            VStack(spacing: 2) {
                if options.showWifi {
                    let wifi = StatusGlyphs.wifi(powerOn: status.wifiOn, rssi: status.wifiRSSI)
                    popoutIcon(.wifi, help: wifiHelp) {
                        Image(systemName: wifi.symbol, variableValue: wifi.strength)
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                if options.showBluetooth {
                    popoutIcon(.bluetooth, help: bluetoothHelp) {
                        BluetoothRune()
                            .stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                            .frame(width: 10, height: 15)
                            .opacity(status.bluetoothOn == false ? 0.4 : 1)
                    }
                }
                if let battery {
                    popoutIcon(.battery, help: StatusGlyphs.batteryText(status.battery)) {
                        Image(systemName: battery)
                            .font(.system(size: 13, weight: .semibold))
                            .rotationEffect(.degrees(-90))
                    }
                }
            }
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.08), in: .capsule)
        }
    }

    /// Symbolknopf, der seinen Rahmen fuer die Lage des Popouts meldet.
    private func popoutIcon<Glyph: View>(
        _ kind: StatusPopoutKind, help: String, @ViewBuilder glyph: @escaping () -> Glyph
    ) -> some View {
        let active = popout?.isOpen == true && popout?.shown == kind
        return SidebarIcon(help: help, action: { popout?.onIconClick(kind) }, content: glyph)
            .background(Color.primary.opacity(active ? 0.14 : 0), in: .rect(cornerRadius: 9))
            .animation(.easeOut(duration: 0.12), value: active)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { popout?.iconFrames[kind] = $0 }
    }

    private var wifiHelp: String {
        guard status.wifiOn else { return String(localized: "WLAN aus") }
        guard let rssi = status.wifiRSSI, rssi != 0 else { return String(localized: "WLAN an, nicht verbunden") }
        return String(localized: "WLAN \(rssi) dBm")
    }

    private var bluetoothHelp: String {
        switch status.bluetoothOn {
        case true?: String(localized: "Bluetooth an")
        case false?: String(localized: "Bluetooth aus")
        case nil: "Bluetooth"
        }
    }
}

/// Symbolknopf der Leiste: 32 x 32, beim Ueberfahren leicht hinterlegt.
/// Ohne Aktion (Statussymbole) ist er nur Anzeige, schimmert aber trotzdem.
struct SidebarIcon<Content: View>: View {
    let help: String
    var action: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @State private var hovering = false
    @Environment(\.barPreview) private var preview
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    init(help: String, action: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.help = help
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: { action?() }) {
            content()
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(hovering ? 0.14 : 0), in: .rect(cornerRadius: 9))
                .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        // Mit Theme faerbt `--apollo-bar-icon-color` die Zeichen der Leiste.
        .foregroundStyle(style.declaresColor(.barIcon) ? AnyShapeStyle(style.barIcon) : AnyShapeStyle(.primary))
        // Nicht `onHover`: die Leiste gehoert einer nie aktiven App, dort blieb
        // der Hover-Effekt stehen, wenn die Maus wegging.
        .background {
            if !preview { HoverTracker { hovering = $0 } }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Bluetooth-Rune, selbst gezeichnet: Apple bietet dafuer kein SF Symbol an
/// (das Logo ist markenrechtlich geschuetzt). Geometrie im 10 x 15-Rahmen.
struct BluetoothRune: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let x0 = rect.minX, y0 = rect.minY
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x0 + x * w, y: y0 + y * h) }
        var path = Path()
        // Links oben diagonal nach rechts unten, zur Spitze unten, senkrecht
        // hoch, zur Spitze rechts oben, diagonal nach links unten.
        path.move(to: p(0, 0.27))
        path.addLine(to: p(1, 0.73))
        path.addLine(to: p(0.5, 1))
        path.addLine(to: p(0.5, 0))
        path.addLine(to: p(1, 0.27))
        path.addLine(to: p(0, 0.73))
        return path
    }
}

/// Die Leiste gehoert zu einer App, die nie im Vordergrund ist. Normale
/// Ansichten verschlucken dann den ersten Klick (er holt nur das Fenster
/// nach vorne); diese nimmt ihn direkt an.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
