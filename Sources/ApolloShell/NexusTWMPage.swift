import ApolloShellCore
import SwiftUI

/// Nexus > TWM: the tiling window manager's switch and options, and its keys.
struct NexusTWMPage: View {
    let model: NexusPanelModel
    @Environment(\.shellStyle) private var style

    var body: some View {
        @Bindable var store = model.settings
        let twm = $store.settings.twm
        VStack(spacing: 8) {
            NexusSwitchCard(symbol: "rectangle.split.3x1", title: "Tiling",
                            subtitle: "Arranges windows side by side, Hyprland style. Needs Accessibility.",
                            isOn: twm.enabled)
            NexusSwitchCard(symbol: "cursorarrow.motionlines", title: "Focus Follows Mouse",
                            subtitle: "The window under the mouse comes forward.",
                            isOn: twm.focusFollowsMouse) {
                slider(value: twm.focusDelay,
                    range: Double(TWMSettings.focusDelayRange.lowerBound)...Double(TWMSettings.focusDelayRange.upperBound),
                    label: "\(store.settings.twm.focusDelayMilliseconds) ms")
                    .disabled(!store.settings.twm.focusFollowsMouse)
            }
            NexusCard(symbol: "square.split.2x2", title: "Gaps", subtitle: "Between windows and around them.") {
                EmptyView()
            } footer: {
                VStack(spacing: 6) {
                    slider(value: twm.innerGap, range: TWMSettings.gapRange,
                           label: "Between \(Int(store.settings.twm.innerGap)) pt")
                    slider(value: twm.outerGap, range: TWMSettings.gapRange,
                           label: "Around \(Int(store.settings.twm.outerGap)) pt")
                }
            }
            NexusCard(symbol: "square.dashed", title: "Border", subtitle: "Around the focused window. 0 hides it.") {
                EmptyView()
            } footer: {
                VStack(spacing: 6) {
                    slider(value: twm.borderWidth, range: TWMSettings.borderWidthRange,
                           label: String(format: "Width %.1f pt", store.settings.twm.borderWidth))
                    slider(value: twm.borderRadius, range: TWMSettings.borderRadiusRange,
                           label: "Corners \(Int(store.settings.twm.borderRadius)) pt")
                }
            }
            NexusCard(symbol: "wind", title: "Glide", subtitle: "How windows move to their place.") {
                EmptyView()
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: twm.resize) {
                        Text("Smart").tag(TWMSettings.Resize.proxy)
                        Text("Smooth").tag(TWMSettings.Resize.smooth)
                        Text("Snap").tag(TWMSettings.Resize.snap)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(resizeHint(store.settings.twm.resize))
                        .font(style.font(size: 11))
                        .foregroundStyle(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    slider(value: twm.glideDuration, range: TWMSettings.glideRange,
                           label: String(format: "%.2f s", store.settings.twm.glideDuration))
                }
            }
            NexusCard(symbol: "keyboard", title: "Keys", subtitle: "Super is fn held.") {
                EmptyView()
            } footer: {
                VStack(alignment: .leading, spacing: 3) {
                    configFile
                    ForEach(Self.keys, id: \.0) { keys, action in
                        HStack(alignment: .firstTextBaseline) {
                            Text(keys).font(style.font(size: 11, weight: .semibold)).frame(width: 110, alignment: .leading)
                            Text(action).font(style.font(size: 11)).foregroundStyle(style.secondaryText)
                        }
                    }
                }
            }
        }
    }

    /// twm.conf: open it, and what in it could not be read.
    @ViewBuilder private var configFile: some View {
        let file = TWMConfigFile.shared
        HStack {
            Text("Change keys and add app rules in twm.conf.")
                .font(style.font(size: 11))
                .foregroundStyle(style.secondaryText)
            Spacer()
            Button("Open") { file.open() }
                .font(style.font(size: 11))
        }
        ForEach(file.config.problems, id: \.self) { problem in
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(style.font(size: 11))
                .foregroundStyle(.orange)
        }
        Divider().padding(.vertical, 3)
    }

    private func resizeHint(_ resize: TWMSettings.Resize) -> LocalizedStringKey {
        switch resize {
        case .proxy: "Sizes glide; slow apps glide as a picture and redraw once."
        case .smooth: "Sizes glide for every app. Slow apps may stutter."
        case .snap: "Only the position glides; sizes jump. Lightest."
        }
    }

    private func slider(value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        HStack(spacing: 8) {
            Slider(value: value, in: range).tint(style.accent)
            Text(label)
                .font(style.font(size: 11))
                .foregroundStyle(style.secondaryText)
                .monospacedDigit()
                .frame(width: 96, alignment: .trailing)
        }
    }

    private static let keys: [(String, String)] = [
        ("Super + arrows", "focus the neighbor"),
        ("Super + H J K L", "swap with the neighbor"),
        ("Super + Tab", "next window"),
        ("Super + T", "turn the split"),
        ("Super + - / =", "narrower / wider"),
        ("Super + R", "resize with arrows, Esc ends"),
        ("Super + E", "even out all splits"),
        ("Super + G", "join / leave a tab group"),
        ("Super + [ / ]", "previous / next tab"),
        ("Super + Space", "float / tile"),
        ("Super + F", "fill the area"),
        ("Super + Q", "close the window"),
        ("Super + Return", "new terminal"),
        ("Super + 1–9", "desktop 1–9"),
        ("Super + M, 1–9", "send the window to desktop 1–9"),
        ("Super + S", "scratchpad: keep / show / hide"),
        ("Super + drag", "move from anywhere"),
        ("Super + right drag", "resize"),
    ]
}
