import AppKit
import ApolloShellCore
import SwiftUI

/// The content of the left bar: the building blocks out of Nexus > Bar
/// (settings.bar.layout) from top to bottom, each one through `BarModuleView`.
///
/// The default (the "Caelestia" template) is Caelestia's bar (logo,
/// workspaces, spacer, activeWindow, spacer, tray, clock, statusIcons,
/// power): dashboard, spaces, Dock, clock, utilities, status capsule, power.
/// The Dock stands where the active window stands in Caelestia; there is no
/// tray, and utilities sits in its place.
///
/// The models of the seven old blocks always run (so one that is added again
/// is up to date right away); CPU and weather only measure while their block
/// can be seen.
struct SidebarContent: View {
    let settings: ShellSettingsStore
    let context: BarModuleContext

    @Environment(\.shellStyle) private var style

    var body: some View {
        let entries = settings.settings.bar.layout.entries
        // With a theme, `--apollo-bar-item-spacing` and `--apollo-bar-padding`
        // set the gap between the blocks and the margin.
        BarStack(spacing: style.barItemSpacing(8)) {
            ForEach(entries) { entry in
                BarModuleView(entry: entry, context: context)
            }
        }
        // 10 at the top and the bottom: before the kit this margin sat on the
        // dashboard and the power symbol - as a margin of the bar it counts
        // for every arrangement.
        .padding(.vertical, style.barPadding(10))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Reordering in Nexus glides visibly instead of jumping.
        .animation(SidebarMotion.spatial, value: entries.map(\.id))
    }
}

/// The blocks below each other, 8 apart. Fixed ones get their height, the
/// flexible ones (Dock, spacer) share the rest in equal parts - the rules and
/// the tests are in `BarFlex`. A layout of its own instead of a VStack: there
/// the split between several flexible ones hangs on their minimum and ideal
/// sizes (a Dock with a scrolling list against an empty spacer); here it is
/// set. With exactly one flexible one it is the same as the VStack before the
/// kit (image sample: pixel for pixel).
struct BarStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        if let height = proposal.height { return CGSize(width: width, height: height) }
        // Ideal: only the fixed ones, flexible ones count 0.
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

/// Marks a building block as flexible for `BarStack`.
struct BarFlexible: LayoutValueKey {
    static let defaultValue = false
}

/// A building block by its kind - the one place where every kind gets its
/// view. A new kind needs a case here (the compiler asks for it), its options
/// in ApolloShellCore and its editor in Nexus.
///
/// Blocks that can show nothing (spaces without a desktop list, the battery
/// on a desktop Mac) draw nothing and then get no gap either - as in the
/// VStack before.
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
            // Fills the height between the upper and the lower group and
            // stands there in the middle - Caelestia's two spacers.
            SidebarDock(model: context.dock, options: options)
                .layoutValue(key: BarFlexible.self, value: true)
        case .clock(let options):
            SidebarClock(model: context.clock, showIcon: options.showIcon, showDate: options.showDate)
                // A click opens the dashboard with the calendar.
                .contentShape(.rect)
                .onTapGesture { context.onDashboard() }
        case .utilitiesButton:
            SidebarIcon(help: String(localized: "Utilities (SUPER+U)"), action: context.onUtilities) {
                // With `icons/bar-utilities.png` in the theme, that image stands there.
                ThemedIcon("bar-utilities")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
        case .statusIcons(let options):
            StatusCapsule(status: context.status, options: options)
        case .power:
            SidebarIcon(help: String(localized: "Session"), action: context.onPower) {
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
            // Like the rule in the Dock between pinned and running ones.
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
            SidebarIcon(help: String(localized: "Media"), action: { context.onDashboardTab(.media) }) {
                Image(systemName: "music.note")
                    .font(.system(size: 15, weight: .semibold))
            }
        }
    }
}

/// The status symbols below each other in a capsule with a slightly set-off
/// background (Caelestia: StatusIcons, radius "full"). Which ones is decided
/// by Nexus; when none is left, the capsule falls away entirely.
/// A click opens the detail window next to it (`StatusPopout`); the symbol of
/// the open one stays backed. The model comes out of the environment - when
/// it is missing (preview, image samples), the symbols are display only.
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
                        // Theme: icons/status-wifi.png or status-wifi-off.png.
                        ThemedIcon(status.wifiOn == false ? "status-wifi-off" : "status-wifi",
                                   fallback: wifi.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 16, height: 16)
                    }
                }
                if options.showBluetooth {
                    popoutIcon(.bluetooth, help: bluetoothHelp) {
                        // Without a theme the drawn glyph (SF Symbols has none
                        // for Bluetooth), with a theme its image.
                        BluetoothGlyph(on: status.bluetoothOn != false)
                    }
                }
                if let battery {
                    popoutIcon(.battery, help: StatusGlyphs.batteryText(status.battery)) {
                        ThemedIcon(status.battery?.charging == true ? "status-battery-charging" : "status-battery",
                                   fallback: battery)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 15, height: 15)
                            .rotationEffect(.degrees(-90))
                    }
                }
            }
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.08), in: .capsule)
        }
    }

    /// A symbol button that reports its frame for the placement of the popout.
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
        guard status.wifiOn else { return String(localized: "Wi-Fi Off") }
        guard let rssi = status.wifiRSSI, rssi != 0 else { return String(localized: "Wi-Fi On, Not Connected") }
        return String(localized: "Wi-Fi \(rssi) dBm")
    }

    private var bluetoothHelp: String {
        switch status.bluetoothOn {
        case true?: String(localized: "Bluetooth On")
        case false?: String(localized: "Bluetooth Off")
        case nil: "Bluetooth"
        }
    }
}

/// Symbol button of the bar: 32 x 32, slightly backed on hover. Without an
/// action (status symbols) it is display only, but it still shimmers.
struct SidebarIcon<Content: View>: View {
    let help: String
    var action: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @State private var hovering = false
    @Environment(\.barPreview) private var preview
    @Environment(\.shellStyle) private var style

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
        // With a theme, `--apollo-bar-icon-color` colors the glyphs of the bar.
        .foregroundStyle(style.paint(.barIcon, or: .primary))
        // Not `onHover`: the bar belongs to an app that is never active, and
        // the hover effect stayed put there when the mouse left.
        .background {
            if !preview { HoverTracker { hovering = $0 } }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The Bluetooth rune, drawn by hand: Apple offers no SF Symbol for it (the
/// logo is a trademark). The geometry in a 10 x 15 frame.
/// Bluetooth in the bar: with a theme its image, otherwise the drawn glyph -
/// SF Symbols has none for it.
struct BluetoothGlyph: View {
    let on: Bool

    @Environment(\.shellStyle) private var style

    var body: some View {
        let id = on ? "status-bluetooth" : "status-bluetooth-off"
        if style.iconFile(id) != nil {
            ThemedIcon(id, fallback: "")
                .frame(width: 15, height: 15)
                .opacity(on ? 1 : 0.4)
        } else {
            BluetoothRune()
                .stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                .frame(width: 10, height: 15)
                .opacity(on ? 1 : 0.4)
        }
    }
}

struct BluetoothRune: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let x0 = rect.minX, y0 = rect.minY
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x0 + x * w, y: y0 + y * h) }
        var path = Path()
        // From the top left diagonally to the bottom right, to the tip at the
        // bottom, straight up, to the tip at the top right, diagonally down left.
        path.move(to: p(0, 0.27))
        path.addLine(to: p(1, 0.73))
        path.addLine(to: p(0.5, 1))
        path.addLine(to: p(0.5, 0))
        path.addLine(to: p(1, 0.27))
        path.addLine(to: p(0, 0.73))
        return path
    }
}

/// The bar belongs to an app that is never in the foreground. Normal views
/// then swallow the first click (it only brings the window forward); this one
/// takes it straight away.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
