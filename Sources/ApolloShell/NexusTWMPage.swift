import ApolloShellCore
import SwiftUI

/// Nexus > TWM: the tiling window manager's switch and options, and its keys.
/// Everything but the main switch sits in sections one can fold away, so the
/// page stays short while every setting is reachable.
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

            NexusSection("Focus", symbol: "cursorarrow.motionlines", id: "twm.focus", openByDefault: true) {
                NexusSwitchCard(symbol: "cursorarrow.motionlines", title: "Focus Follows Mouse",
                                subtitle: "The window under the mouse comes forward.",
                                isOn: twm.focusFollowsMouse) {
                    slider(value: twm.focusDelay,
                        range: Double(TWMSettings.focusDelayRange.lowerBound)...Double(TWMSettings.focusDelayRange.upperBound),
                        label: "\(store.settings.twm.focusDelayMilliseconds) ms")
                        .disabled(!store.settings.twm.focusFollowsMouse)
                }
                NexusCard(symbol: "square.dashed", title: "Border",
                          subtitle: "Around the focused window. 0 hides it.") {
                    EmptyView()
                } footer: {
                    VStack(spacing: 6) {
                        slider(value: twm.borderWidth, range: TWMSettings.borderWidthRange,
                               label: String(format: "Width %.1f pt", store.settings.twm.borderWidth))
                        slider(value: twm.borderRadius, range: TWMSettings.borderRadiusRange,
                               label: "Corners \(Int(store.settings.twm.borderRadius)) pt")
                    }
                }
            }

            NexusSection("Layout", symbol: "square.split.2x2", id: "twm.layout") {
                NexusCard(symbol: "square.split.2x2", title: "Gaps",
                          subtitle: "Between windows and around them.") {
                    EmptyView()
                } footer: {
                    VStack(spacing: 6) {
                        slider(value: twm.innerGap, range: TWMSettings.gapRange,
                               label: "Between \(Int(store.settings.twm.innerGap)) pt")
                        slider(value: twm.outerGap, range: TWMSettings.gapRange,
                               label: "Around \(Int(store.settings.twm.outerGap)) pt")
                    }
                }
                NexusCard(symbol: "rectangle.topthird.inset.filled", title: "Tab Bars",
                          subtitle: "Height of the strip above a group of windows.") {
                    EmptyView()
                } footer: {
                    slider(value: twm.tabBarHeight, range: TWMSettings.tabBarRange,
                           label: "\(Int(store.settings.twm.tabBarHeight)) pt")
                }
                NexusCard(symbol: "macwindow.on.rectangle", title: "Scratchpad",
                          subtitle: "How much of the screen the window kept at hand covers (Super + S).") {
                    EmptyView()
                } footer: {
                    slider(value: twm.scratchpadShare, range: TWMSettings.scratchpadRange,
                           label: "\(Int(store.settings.twm.scratchpadShare * 100)) %")
                }
            }

            NexusSection("Motion", symbol: "wind", id: "twm.motion") {
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
            }

            NexusSection("Keys", symbol: "keyboard", id: "twm.keys") {
                NexusSwitchCard(symbol: "square.grid.3x1.below.line.grid.1x2", title: "Apple's Desktops",
                                subtitle: "Super + 1–9 switches macOS desktops. Off: the TWM's own workspaces.",
                                isOn: twm.appleDesktops)
                NexusCard(symbol: "arrow.left.and.right", title: "Key Resizing",
                          subtitle: "How far one arrow moves an edge in Super + R.") {
                    EmptyView()
                } footer: {
                    VStack(spacing: 6) {
                        slider(value: twm.resizeStep, range: TWMSettings.resizeStepRange,
                               label: "\(Int(store.settings.twm.resizeStep * 100)) %")
                        slider(value: twm.modeTimeout, range: TWMSettings.modeTimeoutRange,
                               label: String(format: "Mode ends after %.0f s", store.settings.twm.modeTimeout))
                    }
                }
                NexusCard(symbol: "apple.terminal", title: "Terminal",
                          subtitle: "Opened by Super + Return. Empty: kitty, Ghostty or Terminal.") {
                    EmptyView()
                } footer: {
                    TextField("Bundle id", text: twm.terminal)
                        .textFieldStyle(.roundedBorder)
                        .font(style.font(size: 11))
                }
                NexusCard(symbol: "doc.plaintext", title: "Keys and Rules", subtitle: "Super is fn held.") {
                    EmptyView()
                } footer: {
                    VStack(alignment: .leading, spacing: 3) {
                        configFile
                        ForEach(Self.keys, id: \.0) { keys, action in
                            HStack(alignment: .firstTextBaseline) {
                                Text(keys).font(style.font(size: 11, weight: .semibold))
                                    .frame(width: 110, alignment: .leading)
                                Text(action).font(style.font(size: 11)).foregroundStyle(style.secondaryText)
                            }
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

/// A group of cards behind one line that folds away. Whether it stands open
/// is remembered per section, so the page opens the way it was left.
struct NexusSection<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder let content: () -> Content
    @AppStorage private var open: Bool
    @Environment(\.shellStyle) private var style

    init(_ title: LocalizedStringKey, symbol: String, id: String, openByDefault: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content
        _open = AppStorage(wrappedValue: openByDefault, "nexus.section.\(id)")
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(style.font(size: 15))
                        .foregroundStyle(style.accent)
                        .frame(width: 24)
                    Text(title).font(style.font(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(style.font(size: 11, weight: .semibold))
                        .foregroundStyle(style.secondaryText)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(radius: 14)
                .contentShape(.rect)
            }
            .buttonStyle(NexusPressStyle())
            .accessibilityAddTraits(open ? [.isSelected] : [])
            if open {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
