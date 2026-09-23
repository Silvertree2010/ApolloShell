import AppKit
import ApolloShellCore
import SwiftUI

// The blocks of stage 3 (spec "Etappe 3: Module"): now playing, window title,
// input source, volume, system stats. Wi-Fi and Bluetooth on their own are the
// status capsule with one symbol (SidebarContent.swift). Every block lies
// along a top or bottom bar (text beside the symbol) and stands compact across
// the sidebar and the right bar, where 32 points leave room for a symbol and a
// short number, never for a title.

// MARK: - Now playing

/// Title · artist and ‹ ▶ ›. The text is cut to `maxLength` characters
/// rather than scrolled: a marquee would redraw the bar many times a second
/// for as long as music plays. A click on the text opens the dashboard's media
/// page; across a vertical bar only the cover (or a note) and play/pause.
struct BarNowPlayingModule: View {
    let media: MediaModel
    let options: BarNowPlayingOptions
    let onOpen: () -> Void
    @Environment(\.barAxis) private var axis
    @Environment(\.barControlSize) private var size

    var body: some View {
        let playing = media.nowPlaying
        let line = playing.map { BarText.nowPlaying(title: $0.title, artist: $0.artist) } ?? ""
        let help = line.isEmpty ? String(localized: "Nothing Playing") : line
        Group {
            if axis == .horizontal {
                HStack(spacing: 2) {
                    BarTile(help: help, action: onOpen) {
                        HStack(spacing: 6) {
                            cover(side: 18)
                            if !line.isEmpty {
                                Text(BarText.truncated(line, maxLength: options.maxLength))
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                    }
                    if options.showControls, let playing {
                        BarGlyphButton(symbol: "backward.fill", help: String(localized: "Previous")) {
                            media.send(.previousTrack)
                        }
                        BarGlyphButton(symbol: playing.isPlaying ? "pause.fill" : "play.fill",
                                       help: playing.isPlaying ? String(localized: "Pause") : String(localized: "Play")) {
                            media.send(.togglePlayPause)
                        }
                        BarGlyphButton(symbol: "forward.fill", help: String(localized: "Next")) {
                            media.send(.nextTrack)
                        }
                    }
                }
            } else {
                VStack(spacing: 2) {
                    SidebarIcon(help: help, action: onOpen) {
                        cover(side: CGFloat(22).fitting(control: size))
                    }
                    if options.showControls, let playing {
                        SidebarIcon(help: playing.isPlaying ? String(localized: "Pause") : String(localized: "Play"),
                                    action: { media.send(.togglePlayPause) }) {
                            Image(systemName: playing.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
            }
        }
        .onAppear { media.acquire() }
        .onDisappear { media.release() }
    }

    /// The cover while something plays, a note otherwise - a note in grey
    /// when nothing plays, so the block stays in place and says so.
    @ViewBuilder
    private func cover(side: CGFloat) -> some View {
        if media.nowPlaying != nil, let artwork = media.artwork {
            Image(nsImage: artwork)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(.rect(cornerRadius: 4))
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: side, height: side)
                .foregroundStyle(media.nowPlaying == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
    }
}

/// A narrow symbol button for a row of controls: the full height of the bar,
/// only 22 wide - three 32-point buttons would make the block twice as long.
struct BarGlyphButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.barPreview) private var preview
    @Environment(\.barControlSize) private var size

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: size)
                .background(Color.primary.opacity(hovering ? 0.14 : 0), in: .rect(cornerRadius: 7))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background {
            if !preview { HoverTracker { hovering = $0 } }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Window title

/// The frontmost app, with its focused window's title on request. Across a
/// vertical bar only the app's icon.
struct BarWindowTitleModule: View {
    let model: BarFrontAppModel
    let options: BarWindowTitleOptions
    @Environment(\.barAxis) private var axis
    @Environment(\.barControlSize) private var size

    var body: some View {
        let app = model.app
        let name = app?.name ?? ""
        let title = options.showTitle ? model.title : nil
        let help = title.map { $0.isEmpty || $0 == name ? name : "\(name) – \($0)" } ?? name
        Group {
            if axis == .horizontal {
                BarTile(help: help) {
                    HStack(spacing: 6) {
                        if options.showIcon { icon(app, side: 16) }
                        Text(BarText.truncated(BarText.windowLine(app: name, title: title, withIcon: options.showIcon),
                                               maxLength: options.maxLength))
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            } else {
                SidebarIcon(help: help) { icon(app, side: CGFloat(24).fitting(control: size)) }
            }
        }
        // `task(id:)` instead of appear/disappear: switching the title
        // option on or off while the block stands has to move the count
        // along, and the task restarts with the option.
        .task(id: options.showTitle) {
            let wantsTitle = options.showTitle
            model.acquire(wantsTitle: wantsTitle)
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
            model.release(wantsTitle: wantsTitle)
        }
    }

    @ViewBuilder
    private func icon(_ app: BarFrontAppModel.FrontApp?, side: CGFloat) -> some View {
        if let image = app?.icon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
        } else {
            Image(systemName: "macwindow")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: side, height: side)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Input source

/// The short name of the keyboard layout; a click switches to the next one.
/// As a pill in `--apollo-status-keyboard-color` when the bar asks for pills.
struct BarKeyboardModule: View {
    let model: BarKeyboardModel
    let options: BarKeyboardLayoutOptions
    @Environment(\.barAxis) private var axis
    @Environment(\.barStatusStyle) private var statusStyle
    @Environment(\.shellStyle) private var shellStyle

    var body: some View {
        let help = model.name.isEmpty ? String(localized: "Input Source") : model.name
        let horizontal = axis == .horizontal
        Group {
            if statusStyle == .pills {
                BarStatusPill(colors: shellStyle.statusPill(.statusKeyboard), help: help, text: nil,
                              action: model.selectNext) {
                    if options.showIcon && horizontal {
                        Image(systemName: "keyboard")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text(model.short)
                        .font(shellStyle.font(size: horizontal ? 11 : 9.5, weight: .bold))
                        .lineLimit(1)
                        .fixedSize()
                }
            } else {
                BarTile(help: help, action: model.selectNext) {
                    axis.stack(spacing: 2, horizontal: 4) {
                        if options.showIcon {
                            Image(systemName: "keyboard")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(model.short)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .onAppear { model.acquire() }
        .onDisappear { model.release() }
    }
}

// MARK: - Volume

/// Volume symbol and percent, the device's name on request (along a
/// horizontal bar). Scrolling over it steps by 5 %, a click mutes.
struct BarVolumeModule: View {
    let model: BarVolumeModel
    let options: BarVolumeOptions
    @Environment(\.barAxis) private var axis
    @Environment(\.barPreview) private var preview
    @Environment(\.barStatusStyle) private var statusStyle
    @Environment(\.shellStyle) private var shellStyle

    var body: some View {
        let horizontal = axis == .horizontal
        let symbol = VolumeGlyphs.symbol(volume: model.volume, muted: model.muted)
        let percent = "\(VolumeGlyphs.percent(model.volume))%"
        let device = options.showDevice && horizontal && !model.deviceName.isEmpty
            ? BarText.truncated(model.deviceName, maxLength: 24) : nil
        let help = [model.muted ? String(localized: "Volume \(percent), Muted") : String(localized: "Volume \(percent)"),
                    model.deviceName].filter { !$0.isEmpty }.joined(separator: " · ")
        Group {
            if statusStyle == .pills {
                BarStatusPill(colors: shellStyle.statusPill(.statusVolume), help: help,
                              text: [options.showPercent ? percent : nil, device].compactMap { $0 }.joined(separator: " · "),
                              action: model.toggleMute) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 15, height: 13)
                }
            } else {
                BarTile(help: help, action: model.toggleMute) {
                    axis.stack(spacing: 3, horizontal: 4) {
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .semibold))
                            // The widest symbol sets the width: no jumping
                            // between one and three waves.
                            .frame(width: 18, height: 15, alignment: horizontal ? .leading : .center)
                        if options.showPercent {
                            Text(percent)
                                .font(.system(size: 10.5, weight: .semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        if let device {
                            Text(device)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
            }
        }
        .background {
            if !preview { ScrollWheelCatcher { model.step(by: $0) } }
        }
        .onAppear { model.acquire() }
        .onDisappear { model.release() }
    }
}

/// Hands scroll-wheel steps over the view to `onSteps`, without taking any
/// clicks: a local event monitor, active only while the view is in a window,
/// that looks at scroll events inside the view's bounds. An NSView that
/// overrode `scrollWheel` would have to be hit-tested, and then it would
/// swallow the button's clicks too.
struct ScrollWheelCatcher: NSViewRepresentable {
    let onSteps: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView(onSteps: onSteps) }

    func updateNSView(_ view: CatcherView, context: Context) { view.onSteps = onSteps }

    final class CatcherView: NSView {
        var onSteps: (Int) -> Void
        private var monitor: Any?
        private var stepper = ScrollStepper()

        init(onSteps: @escaping (Int) -> Void) {
            self.onSteps = onSteps
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            } else if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    // Local monitors run on the main thread, inside
                    // `sendEvent`; only the verdict crosses the isolation
                    // boundary, not the non-Sendable event.
                    nonisolated(unsafe) let event = event
                    let swallow = MainActor.assumeIsolated { self?.consumes(event) ?? false }
                    return swallow ? nil : event
                }
            }
        }

        /// `true` swallows the event: the bar has nothing else that scrolls
        /// under the volume block. Momentum after the fingers left is
        /// swallowed unused - the volume should stop when the swipe stops.
        private func consumes(_ event: NSEvent) -> Bool {
            guard let window, event.window === window,
                  bounds.contains(convert(event.locationInWindow, from: nil)) else { return false }
            guard event.momentumPhase.isEmpty else { return true }
            let steps = stepper.steps(delta: Double(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas,
                                      inverted: event.isDirectionInvertedFromDevice)
            if steps != 0 { onSteps(steps) }
            return true
        }
    }
}

// MARK: - System stats

/// CPU and memory in percent, like the sysmon of the Serpantinum top bar.
/// Reads `BarCPUModel` (every 2 s, only while a block needs it); a click
/// opens the performance page.
struct BarSystemStatsModule: View {
    let model: BarCPUModel
    let options: BarSystemStatsOptions
    let onOpen: () -> Void
    @Environment(\.barAxis) private var axis

    var body: some View {
        let cpu = BarText.percent(model.usage)
        let memory = BarText.percent(model.memory)
        let help = [options.shownCPU ? String(localized: "CPU \(cpu)") : nil,
                    options.showMemory ? String(localized: "Memory \(memory)") : nil]
            .compactMap { $0 }.joined(separator: " · ")
        BarTile(help: help, action: onOpen) {
            axis.stack(spacing: 4, horizontal: 8) {
                if options.shownCPU { stat(symbol: "cpu", text: cpu) }
                if options.showMemory { stat(symbol: "memorychip", text: memory) }
            }
        }
        .onAppear { model.acquire() }
        .onDisappear { model.release() }
    }

    private func stat(symbol: String, text: String) -> some View {
        axis.stack(spacing: 1, horizontal: 3) {
            Image(systemName: symbol)
                .font(.system(size: axis == .horizontal ? 11 : 10, weight: .semibold))
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Pills

/// A coloured status pill for blocks outside the status capsule (volume,
/// input source), styled like the capsule's own pills so a bar of pills
/// reads as one family: the symbol and, along a horizontal bar, a word.
struct BarStatusPill<Glyph: View>: View {
    let colors: (fill: Color, text: Color)
    let help: String
    let text: String?
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph
    @Environment(\.barAxis) private var axis
    @Environment(\.barControlSize) private var size
    @Environment(\.shellStyle) private var shellStyle

    var body: some View {
        let horizontal = axis == .horizontal
        // A few points off the bar's edges, like the capsules of a group.
        let across = max(size - 8, 16)
        Button(action: action) {
            HStack(spacing: 4) {
                glyph()
                if horizontal, let text, !text.isEmpty {
                    Text(text)
                        .font(shellStyle.font(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, horizontal ? 8 : 0)
            .frame(width: horizontal ? nil : across, height: across)
            .foregroundStyle(colors.text)
            .background(colors.fill, in: .capsule)
            .frame(width: horizontal ? nil : size, height: horizontal ? size : nil)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
