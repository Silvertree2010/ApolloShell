import AppKit
import ApolloShellCore
import SwiftUI

// The widgets of 09/23 (timer, apps, photos, connection, recent files,
// clipboard, sun and moon, drives). Like the others they shape themselves
// after their frame: 130 tall is a row, 250 and 392 a column or a block.

// MARK: - Timer

/// Timer, stopwatch or pomodoro - the widget's display says which one it
/// starts. There is one timer in the shell (`ShellTimer.shared`): whatever
/// runs is shown, whichever widget started it.
struct TimerCard: View {
    let timer: ShellTimer
    let display: WidgetDisplay
    let minutes: Int
    let size: CGSize
    @Environment(\.shellStyle) private var style

    private var mode: ShellTimerState.Mode {
        switch display {
        case .stopwatch: .stopwatch
        case .pomodoro: .pomodoro
        default: .timer
        }
    }

    var body: some View {
        let state = timer.state
        // Idle: the widget's own mode; running or paused: the one timer.
        let shown = state.isIdle && state.mode != mode ? previewState : state
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = timer.fixedNow ?? context.date
            let text = Self.text(shown, now: now)
            Card(radius: 24) {
                if size.height < 150 && size.width < 200 {
                    // Too narrow for a row: the time in the ring, a tap starts and pauses.
                    ring(shown, now: now, side: min(size.height, size.width) - 24) {
                        Text(text).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                    .onTapGesture {
                        if timer.state.isIdle && timer.state.mode != mode { timer.set(mode: mode, minutes: minutes) }
                        timer.toggle()
                    }
                    .help(shown.isRunning ? "Pause" : "Start")
                } else if size.height < 150 {
                    HStack(spacing: 14) {
                        ring(shown, now: now, side: min(size.height - 32, 84)) {
                            Image(systemName: symbol(shown)).font(style.font(size: 20, weight: .semibold))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            label(shown)
                            Text(text).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        Spacer(minLength: 0)
                        if size.width >= 280 { controls(shown, size: 34) }
                    }
                    .padding(.horizontal, 16)
                } else {
                    let side = min(size.width - 48, size.height - 110, 220)
                    VStack(spacing: 12) {
                        label(shown)
                        ring(shown, now: now, side: side) {
                            Text(text).font(.system(size: side * 0.22, weight: .semibold, design: .rounded))
                                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                        }
                        controls(shown, size: 40)
                    }
                    .padding(14)
                }
            }
            .contentShape(Rectangle())
        }
        .onAppear { timer.prepare(minutes: minutes) }
    }

    /// What an idle widget of another mode shows: its own start value.
    private var previewState: ShellTimerState {
        var state = ShellTimerState()
        state.set(mode: mode, length: TimeInterval(minutes * 60))
        return state
    }

    static func text(_ state: ShellTimerState, now: Date) -> String {
        if let remaining = state.remaining(at: now) { return ShellTimerState.text(remaining, countingDown: true) }
        return ShellTimerState.text(state.elapsed(at: now), countingDown: false)
    }

    private func symbol(_ state: ShellTimerState) -> String {
        switch state.mode {
        case .timer: "timer"
        case .stopwatch: "stopwatch"
        case .pomodoro: state.phase == .focus ? "brain.head.profile" : "cup.and.saucer.fill"
        }
    }

    private func label(_ state: ShellTimerState) -> some View {
        let title: String = switch state.mode {
        case .timer: String(localized: "Timer")
        case .stopwatch: String(localized: "Stopwatch")
        case .pomodoro:
            switch state.phase {
            case .focus: String(localized: "Focus")
            case .shortBreak: String(localized: "Short Break")
            case .longBreak: String(localized: "Long Break")
            }
        }
        return Text(title).font(style.font(size: 13, weight: .semibold)).foregroundStyle(style.accent).lineLimit(1)
    }

    private func ring<Content: View>(_ state: ShellTimerState, now: Date, side: CGFloat,
                                     @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: side * 0.07)
            Circle()
                .trim(from: 0, to: state.mode == .stopwatch ? state.progress(at: now) : 1 - state.progress(at: now))
                .stroke(style.accent, style: StrokeStyle(lineWidth: side * 0.07, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: state.progress(at: now))
            content().padding(side * 0.14)
        }
        .frame(width: side, height: side)
    }

    private func controls(_ state: ShellTimerState, size: CGFloat) -> some View {
        HStack(spacing: 8) {
            if state.isIdle && state.mode == .timer && mode == .timer {
                round("minus", size: size) { timer.adjust(minutes: -1) }
                round("plus", size: size) { timer.adjust(minutes: 1) }
            } else {
                round("arrow.counterclockwise", size: size) { timer.reset() }
                    .disabled(state.isIdle)
            }
            Button {
                if timer.state.isIdle && timer.state.mode != mode { timer.set(mode: mode, minutes: minutes) }
                timer.toggle()
            } label: {
                Image(systemName: state.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(style.onAccent)
                    .frame(width: size * 1.6, height: size)
                    .background(style.accent, in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .help(state.isRunning ? "Pause" : "Start")
        }
    }

    private func round(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .frame(width: size, height: size)
                .background(Color.primary.opacity(0.08), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Apps

/// Favourite apps: a grid of icons, or a list with their names. A click
/// starts the app or brings it to the front, like the Dock.
struct AppsCard: View {
    let bundleIDs: [String]
    let list: Bool
    let size: CGSize
    @Environment(\.shellStyle) private var style

    var body: some View {
        let apps = bundleIDs.compactMap { id in BarApps.info(for: id).map { (id, $0) } }
        Card(radius: 24) {
            if apps.isEmpty {
                ExtraEmptyState(symbol: "square.grid.3x3", text: String(localized: "Add apps in the widget's options"))
            } else if list {
                let rows = max(1, Int((size.height - 20) / 34))
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(apps.prefix(rows), id: \.0) { id, info in
                        Button { BarApps.open(id) } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: info.icon).resizable().frame(width: 26, height: 26)
                                Text(info.name).font(style.font(size: 13, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 32)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            } else {
                let icon = Self.iconSize(count: apps.count, in: size)
                let columns = max(1, Int((size.width - 24) / (icon + 12)))
                LazyVGridless(columns: columns, spacing: 12) {
                    ForEach(apps, id: \.0) { id, info in
                        Button { BarApps.open(id) } label: {
                            Image(nsImage: info.icon).resizable().frame(width: icon, height: icon)
                        }
                        .buttonStyle(.plain)
                        .help(info.name)
                    }
                }
                .padding(12)
            }
        }
    }

    /// As large as fits all apps, between 40 and 72.
    static func iconSize(count: Int, in size: CGSize) -> CGFloat {
        for side in stride(from: 72.0, through: 40, by: -4) {
            let columns = max(1, Int((size.width - 24) / (side + 12)))
            let rows = Int((size.height - 24) / (side + 12))
            if columns * max(rows, 1) >= count { return side }
        }
        return 40
    }
}

/// A simple grid of fixed columns - `LazyVGrid` stays blank in image samples
/// (`ImageRenderer`, measured 19.09.).
struct LazyVGridless<Content: View>: View {
    let columns: Int
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        FlowGrid(columns: columns, spacing: spacing) { content }
    }
}

private struct FlowGrid: Layout {
    let columns: Int
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let cell = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        let rows = (subviews.count + columns - 1) / columns
        let width = CGFloat(min(columns, subviews.count)) * (cell.width + spacing) - spacing
        return CGSize(width: max(width, 0), height: max(CGFloat(rows) * (cell.height + spacing) - spacing, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cell = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        let used = sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
        let origin = CGPoint(x: bounds.midX - used.width / 2, y: bounds.midY - used.height / 2)
        for (index, subview) in subviews.enumerated() {
            let x = origin.x + CGFloat(index % columns) * (cell.width + spacing)
            let y = origin.y + CGFloat(index / columns) * (cell.height + spacing)
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(cell))
        }
    }
}

// MARK: - Photos

/// A picture of a folder, a new one every five minutes (worked out from the
/// clock, not a timer: every opening shows the right one).
struct PhotoFrameCard: View {
    let photos: PhotoFrames
    let folder: String?
    let size: CGSize
    var fixedNow: Date?
    @Environment(\.shellStyle) private var style

    var body: some View {
        let pictures = photos.pictures(in: folder)
        let radius = style.cardRadius(24)
        TimelineView(.everyMinute) { context in
            let now = fixedNow ?? context.date
            ZStack {
                Rectangle().fill(Color.primary.opacity(0.06))
                if pictures.isEmpty {
                    ExtraEmptyState(symbol: "photo.on.rectangle",
                                    text: String(localized: "No pictures in \(NSString(string: folder ?? PhotoFrames.defaultFolder).lastPathComponent)"))
                } else {
                    let url = pictures[Int(now.timeIntervalSince1970 / 300) % pictures.count]
                    if let image = photos.image(url) {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                            .frame(width: size.width, height: size.height).clipped()
                            .id(url)
                            .transition(.opacity)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            .overlay { style.border(RoundedRectangle(cornerRadius: radius, style: .continuous)) }
            .animation(.easeInOut(duration: 0.6), value: pictures.isEmpty ? 0 : Int(now.timeIntervalSince1970 / 300))
        }
    }
}

// MARK: - Connection

struct NetworkInfoCard: View {
    let model: NetworkInfoModel
    let minimal: Bool
    let size: CGSize
    @Environment(\.shellStyle) private var style

    private var title: String {
        switch model.link {
        case .wifi(let name): name ?? "Wi-Fi"
        case .wired: "Ethernet"
        case .none: String(localized: "Offline")
        }
    }

    private var symbol: String {
        switch model.link {
        case .wifi: "wifi"
        case .wired: "cable.connector"
        case .none: "wifi.slash"
        }
    }

    var body: some View {
        Card(radius: 24) {
            if minimal {
                HStack(spacing: 14) {
                    Image(systemName: symbol).font(style.font(size: 30, weight: .semibold)).foregroundStyle(style.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(style.font(size: 17, weight: .semibold)).lineLimit(1)
                        Text(model.latency.map { "\($0) ms" } ?? "–")
                            .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
            } else {
                VStack(alignment: .leading, spacing: size.height > 200 ? 12 : 6) {
                    HStack(spacing: 8) {
                        Image(systemName: symbol).font(style.font(size: 14, weight: .semibold)).foregroundStyle(style.accent)
                        Text(title).font(style.font(size: 15, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        if let latency = model.latency {
                            Text("\(latency) ms").font(style.font(size: 12, weight: .semibold)).monospacedDigit()
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.primary.opacity(0.08), in: .capsule)
                                .help("Time to reach 1.1.1.1")
                        }
                    }
                    if size.height > 200 { Spacer(minLength: 0) }
                    row(String(localized: "Local"), model.localAddress)
                    row(String(localized: "Public"), model.publicAddress)
                    if size.height > 200 { Spacer(minLength: 0) }
                }
                .padding(16)
            }
        }
    }

    private func row(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title).font(style.font(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value ?? "–").font(style.font(size: 13, weight: .medium)).monospacedDigit().textSelection(.enabled)
        }
    }
}

// MARK: - Recent files

struct RecentFilesCard: View {
    let model: RecentFilesModel
    let grid: Bool
    let size: CGSize
    @Environment(\.shellStyle) private var style

    var body: some View {
        Card(radius: 24) {
            if model.files.isEmpty {
                ExtraEmptyState(symbol: "doc.on.doc", text: String(localized: "Nothing opened this week"))
            } else if grid {
                let icon: CGFloat = size.height < 150 ? 40 : 52
                let columns = max(1, Int((size.width - 24) / (icon + 36)))
                let rows = max(1, Int((size.height - 24) / (icon + 34)))
                FlowGrid(columns: columns, spacing: 10) {
                    ForEach(model.files.prefix(columns * rows)) { file in
                        Button { model.open(file) } label: {
                            VStack(spacing: 4) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable()
                                    .frame(width: icon, height: icon)
                                Text(file.name).font(style.font(size: 10)).lineLimit(1).truncationMode(.middle)
                                    .frame(width: icon + 26)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(file.url.path)
                    }
                }
                .padding(12)
            } else {
                let rows = max(1, Int((size.height - 44) / 30))
                VStack(alignment: .leading, spacing: 0) {
                    ExtraHeader(symbol: "clock.arrow.circlepath", title: String(localized: "Recent Files"))
                    ForEach(model.files.prefix(rows)) { file in
                        Button { model.open(file) } label: {
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable()
                                    .frame(width: 20, height: 20)
                                Text(file.name).font(style.font(size: 13)).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 6)
                                Text(file.used, format: .relative(presentation: .named))
                                    .font(style.font(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(file.url.path)
                        .contextMenu { Button("Show in Finder") { model.reveal(file) } }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
            }
        }
    }
}

// MARK: - Clipboard

struct ClipboardCard: View {
    let history: ClipboardHistory
    let size: CGSize
    @State private var copied: String?
    @Environment(\.shellStyle) private var style

    var body: some View {
        Card(radius: 24) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ExtraHeader(symbol: "list.clipboard", title: String(localized: "Clipboard"))
                    Spacer()
                    if !history.list.items.isEmpty {
                        Button("Clear") { history.clear() }
                            .buttonStyle(.plain).font(style.font(size: 11, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.bottom, 6)
                    }
                }
                if history.list.items.isEmpty {
                    Spacer(minLength: 0)
                    Text("Copied text shows up here. Secrets from password managers never do.")
                        .font(style.font(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                } else {
                    let rows = max(1, Int((size.height - 44) / 30))
                    ForEach(history.list.items.prefix(rows), id: \.self) { text in
                        Button {
                            history.copy(text)
                            copied = text
                        } label: {
                            HStack(spacing: 8) {
                                Text(ClipboardList.preview(text)).font(style.font(size: 13)).lineLimit(1)
                                Spacer(minLength: 6)
                                Image(systemName: copied == text ? "checkmark" : "doc.on.doc")
                                    .font(style.font(size: 11, weight: .semibold))
                                    .foregroundStyle(copied == text ? style.accent : Color.secondary)
                            }
                            .frame(height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Copy again")
                        .contextMenu { Button("Remove", role: .destructive) { history.remove(text) } }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Sun and moon

/// The sun's arc from rise to set with where it stands now, and the moon's
/// phase. Computed from the widget's place (`SunMoon`), nothing fetched.
struct SunCard: View {
    let place: WeatherLocation?
    let minimal: Bool
    let size: CGSize
    var fixedNow: Date?
    @Environment(\.shellStyle) private var style

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = fixedNow ?? context.date
            Card(radius: 28) {
                if let place {
                    content(place: place, now: now)
                } else {
                    ExtraEmptyState(symbol: "location.slash", text: String(localized: "Set a place in the widget's options"))
                }
            }
        }
    }

    @ViewBuilder
    private func content(place: WeatherLocation, now: Date) -> some View {
        let day = SunMoon.day(now, latitude: place.latitude, longitude: place.longitude)
        let phase = SunMoon.moonPhase(now)
        let tall = size.height > 200
        if minimal {
            let stacked = size.width < 300
            let layout = stacked ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(spacing: 18))
            layout {
                times(day, stacked: stacked)
                if !stacked { Spacer(minLength: 0) }
                moon(phase, side: 44, detailed: stacked && tall)
            }
            .padding(.horizontal, 20)
        } else if !tall && size.width < 320 {
            // A narrow row: the arc and the times, the moon only as a symbol on the arc's right.
            VStack(alignment: .leading, spacing: 6) {
                SunArc(day: day, now: now).frame(height: 48)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: SunMoon.moonSymbol(phase: phase)).font(.system(size: 16))
                            .foregroundStyle(Color.primary.opacity(0.85)).help(SunMoon.moonName(phase: phase))
                    }
                times(day)
            }
            .padding(16)
        } else {
            let layout = tall ? AnyLayout(VStackLayout(spacing: 14)) : AnyLayout(HStackLayout(spacing: 16))
            layout {
                VStack(alignment: .leading, spacing: 6) {
                    SunArc(day: day, now: now).frame(height: tall ? 90 : 56)
                    times(day)
                }
                moon(phase, side: tall ? 56 : 44, detailed: size.width >= 320 || tall)
            }
            .padding(16)
        }
    }

    private func times(_ day: SunMoon.Day, stacked: Bool = false) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            time("sunrise.fill", day.sunrise, fallback: day.alwaysUp ? String(localized: "Up all day") : String(localized: "Down all day"))
            time("sunset.fill", day.sunset, fallback: "")
        }
        .fixedSize()
    }

    private func time(_ symbol: String, _ date: Date?, fallback: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).symbolRenderingMode(.multicolor).font(style.font(size: 15))
            Text(date.map { $0.formatted(date: .omitted, time: .shortened) } ?? fallback)
                .font(style.font(size: 15, weight: .semibold)).monospacedDigit().lineLimit(1)
        }
    }

    private func moon(_ phase: Double, side: CGFloat, detailed: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: SunMoon.moonSymbol(phase: phase))
                .font(.system(size: side * 0.8))
                .foregroundStyle(Color.primary.opacity(0.85))
            if detailed {
                VStack(alignment: .leading, spacing: 1) {
                    Text(SunMoon.moonName(phase: phase)).font(style.font(size: 13, weight: .semibold)).lineLimit(1)
                    Text("\(Int((SunMoon.illumination(phase: phase) * 100).rounded())) % lit")
                        .font(style.font(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .help(SunMoon.moonName(phase: phase))
    }
}

/// Half an ellipse from sunrise (left) to sunset (right); the sun sits on
/// it where it is now, or rests at the horizon before and after.
private struct SunArc: View {
    let day: SunMoon.Day
    let now: Date
    @Environment(\.shellStyle) private var style

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            let fraction = progress
            let point = CGPoint(x: fraction * w, y: h - sin(fraction * .pi) * (h - 8))
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 1).offset(y: h - 0.5)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h))
                    for step in 1...40 {
                        let t = Double(step) / 40
                        path.addLine(to: CGPoint(x: t * w, y: h - sin(t * .pi) * (h - 8)))
                    }
                }
                .stroke(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                Circle().fill(Color.yellow).frame(width: 14, height: 14)
                    .shadow(color: .orange.opacity(0.6), radius: 6)
                    .position(point)
            }
        }
    }

    private var progress: Double {
        guard let rise = day.sunrise, let set = day.sunset, set > rise else { return day.alwaysUp ? 0.5 : 0 }
        return min(max(now.timeIntervalSince(rise) / set.timeIntervalSince(rise), 0), 1)
    }
}

// MARK: - Drives

struct DrivesCard: View {
    let model: DrivesModel
    let size: CGSize
    @Environment(\.shellStyle) private var style

    var body: some View {
        Card(radius: 24) {
            if model.drives.isEmpty {
                ExtraEmptyState(symbol: "externaldrive", text: String(localized: "No drives"))
            } else {
                let rows = max(1, Int((size.height - 28) / 50))
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.drives.prefix(rows)) { drive in
                        HStack(spacing: 10) {
                            Image(systemName: drive.ejectable ? "externaldrive.fill" : "internaldrive.fill")
                                .font(style.font(size: 16)).foregroundStyle(style.accent).frame(width: 22)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(drive.name).font(style.font(size: 13, weight: .semibold)).lineLimit(1)
                                    Spacer(minLength: 6)
                                    Text(String(localized: "\(ByteFormat.bytes(Double(drive.free))) free"))
                                        .font(style.font(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                UsageBar(value: drive.usedFraction, height: 6)
                            }
                            if drive.ejectable {
                                Button { model.eject(drive) } label: {
                                    Image(systemName: "eject.fill").font(style.font(size: 11, weight: .semibold))
                                        .frame(width: 26, height: 26)
                                        .background(Color.primary.opacity(0.08), in: .circle)
                                }
                                .buttonStyle(.plain)
                                .help("Eject \(drive.name)")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { model.reveal(drive) }
                    }
                }
                .padding(14)
            }
        }
    }
}

// MARK: - Building blocks

private struct ExtraHeader: View {
    let symbol: String
    let title: String
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(style.font(size: 12, weight: .semibold)).foregroundStyle(style.accent)
            Text(title).font(style.font(size: 13, weight: .semibold))
        }
        .padding(.bottom, 6)
    }
}

struct ExtraEmptyState: View {
    let symbol: String
    let text: String
    @Environment(\.shellStyle) private var style

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(style.font(size: 24, weight: .light)).foregroundStyle(.secondary)
            Text(text).font(style.font(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
