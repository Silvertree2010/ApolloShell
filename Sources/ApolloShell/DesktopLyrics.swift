import AppKit
import ApolloShellCore
import SwiftUI

@MainActor
final class DesktopLyrics {
    private let model: LyricsModel
    private let settings: ShellSettingsStore
    private var slots = ScreenSlots<DesktopLyricsWindow>()
    private var on = false
    private var obs: [Task<Void, Never>] = []

    init(model: LyricsModel, settings: ShellSettingsStore) {
        self.model = model
        self.settings = settings
        obs.append(Task { [weak self, settings] in
            for await s in Observations({ settings.settings.lyrics }) { self?.set(s) }
        })
        obs.append(Task { [weak self, settings] in
            for await _ in Observations({ (settings.settings.bar.screens, settings.settings.background.desktopClock) }) { self?.rebuild() }
        })
        ShellScreens.onChange { [weak self] in self?.rebuild() }
    }

    private func set(_ s: ShellSettings.Lyrics) {
        let want = s.showsDesktop
        if want != on {
            on = want
            if !on { slots.removeAll { $0.tearDown() } }
        }
        rebuild()
    }

    private func rebuild() {
        guard on else { return }
        let m = model
        let s = settings.settings.lyrics
        let clock = settings.settings.background.desktopClock
        slots.distribute(
            on: settings.settings.bar.screens,
            make: { _ in DesktopLyricsWindow(model: m) },
            update: { w, screen in
                w.layout(on: screen, edge: s.desktopEdge, above: s.desktopAbove, lift: clock ? 150 : 0)
                w.show()
            },
            remove: { $0.tearDown() }
        )
    }
}

@MainActor
private final class DesktopLyricsWindow {
    private let window: ShellPanel

    init(model: LyricsModel) {
        let h = NSHostingView(rootView: DesktopLyricsView(model: model).shellTheme())
        h.sizingOptions = []
        window = ShellPanel(level: Self.wallpaper, behavior: [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary],
                            deferred: false)
        window.ignoresMouseEvents = true
        window.contentView = h
    }

    static let wallpaper = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    func layout(on screen: ShellScreen, edge: ShellSettings.LyricsEdge, above: Bool, lift: CGFloat) {
        window.level = above ? .floating : Self.wallpaper
        let v = screen.visibleFrame
        let w = min(v.width - 120, 1200)
        let h: CGFloat = 220
        let y: CGFloat = switch edge {
        case .bottom: v.minY + 40 + lift
        case .top: v.maxY - h - 40
        case .center: v.midY - h / 2
        }
        window.setFrame(NSRect(x: v.midX - w / 2, y: y, width: w, height: h), display: true)
    }

    func show() {
        guard !window.isVisible else { return }
        window.orderFrontRegardless()
    }

    func tearDown() {
        window.orderOut(nil)
    }
}

struct DesktopLyricsView: View {
    let model: LyricsModel
    var base: CGFloat = 44

    var body: some View {
        TimelineView(.animation(paused: !(model.media.nowPlaying?.isPlaying ?? false))) { ctx in
            let f = LyricsFrame(model, at: ctx.date)
            content(f)
        }
        .onAppear { model.acquire() }
        .onDisappear { model.release() }
    }

    @ViewBuilder private func content(_ f: LyricsFrame) -> some View {
        let st = model.style
        GeometryReader { g in
            if let tl = model.timeline, tl.lyrics.synced, model.phase == .ready {
                let n = tl.lyrics.lines.count
                let i = f.idx ?? -1
                let lo = max(0, i - 1), hi = min(n - 1, i + 2)
                ZStack {
                    if lo <= hi {
                        ForEach(lo...hi, id: \.self) { k in
                            row(tl.lyrics.lines[k], r: k - i, f: f, st: st, w: g.size.width)
                                .position(x: g.size.width / 2, y: y(k - i, h: g.size.height))
                        }
                    }
                }
                .animation(st.snap, value: i)
            }
        }
        .clipped()
    }

    private func y(_ r: Int, h: CGFloat) -> CGFloat {
        let c = h * 0.42
        switch r {
        case ..<0: return c - base * 2.4
        case 0: return c
        case 1: return c + base * 1.45
        default: return c + base * 3.4
        }
    }

    @ViewBuilder private func row(_ l: LyricLine, r: Int, f: LyricsFrame, st: LyricsStyle, w: CGFloat) -> some View {
        let act = r == 0
        Group {
            if l.isBreak {
                LyricsBreakDots(prog: act ? f.prog : 0, lit: .white, dim: .white.opacity(0.3), size: base * 0.4)
            } else {
                LyricsLineText(line: l, style: st, size: base, active: act, prog: act ? f.prog : (r < 0 ? 1 : 0),
                               words: act ? f.words : l.w.map { _ in r < 0 ? 1 : 0 },
                               lit: .white, dim: .white.opacity(act ? 0.38 : 0.55), morph: true)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: w - 40)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
        .scaleEffect(act ? 1 + f.beat * st.pulse * 0.06 : 0.5)
        .offset(x: act ? sin(f.pos * 90) * f.beat * st.shake * 3 : 0)
    }

    private func next(_ tl: LyricsTimeline, _ i: Int) -> LyricLine? {
        tl.lyrics.lines.dropFirst(i + 1).first { !$0.isBreak }
    }
}
