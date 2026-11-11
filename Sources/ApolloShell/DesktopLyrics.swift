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
            for await _ in Observations({ settings.settings.bar.screens }) { self?.rebuild() }
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
        slots.distribute(
            on: settings.settings.bar.screens,
            make: { _ in DesktopLyricsWindow(model: m) },
            update: { w, screen in
                w.layout(on: screen, edge: s.desktopEdge, above: s.desktopAbove)
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

    func layout(on screen: ShellScreen, edge: ShellSettings.LyricsEdge, above: Bool) {
        window.level = above ? .floating : Self.wallpaper
        let v = screen.visibleFrame
        let w = min(v.width - 120, 1200)
        let h: CGFloat = 220
        let y: CGFloat = switch edge {
        case .bottom: v.minY + 40
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
        let tl = model.timeline
        ZStack {
            if let tl, tl.lyrics.synced, model.phase == .ready, let i = f.idx, tl.isSung(i, at: f.pos) || !f.gap {
                let l = tl.lyrics.lines[i]
                VStack(spacing: base * 0.25) {
                    if l.isBreak {
                        LyricsBreakDots(prog: f.prog, lit: .white, dim: .white.opacity(0.3), size: base * 0.4)
                    } else {
                        LyricsLineText(line: l, style: st, size: base, active: true, prog: f.prog, words: f.words,
                                       lit: .white, dim: .white.opacity(0.38))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .scaleEffect(1 + f.beat * st.pulse * 0.06)
                            .offset(x: sin(f.pos * 90) * f.beat * st.shake * 3)
                    }
                    if let n = next(tl, i) {
                        LyricsLineText(line: n, style: st, size: base * 0.5, active: false, prog: 0, words: [],
                                       lit: .white, dim: .white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                .shadow(color: .black.opacity(0.55), radius: 10, y: 2)
                .id(i)
                .transition(st.enter)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(st.anim, value: f.idx)
    }

    private func next(_ tl: LyricsTimeline, _ i: Int) -> LyricLine? {
        tl.lyrics.lines.dropFirst(i + 1).first { !$0.isBreak }
    }
}
