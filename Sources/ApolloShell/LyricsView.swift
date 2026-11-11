import ApolloShellCore
import SwiftUI

extension LyricsStyle {
    func font(_ size: CGFloat, active: Bool) -> Font {
        let w = active ? weight : max(0.3, weight - 0.15)
        let fw: Font.Weight = switch w {
        case ..<0.3: .light
        case ..<0.45: .regular
        case ..<0.58: .medium
        case ..<0.7: .semibold
        case ..<0.82: .bold
        case ..<0.92: .heavy
        default: .black
        }
        let d: Font.Design = switch face {
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        case .standard, .condensed: .default
        }
        let f = Font.system(size: size * self.size, weight: fw, design: d)
        return face == .condensed ? f.width(.condensed) : f
    }

    var anim: Animation {
        switch motion {
        case .slam: .spring(response: max(0.12, trans), dampingFraction: 0.62)
        case .pop: .spring(response: trans + 0.08, dampingFraction: 0.58)
        case .rise: .spring(response: trans + 0.1, dampingFraction: 0.86)
        case .drift: .easeInOut(duration: trans + 0.2)
        case .fade: .easeInOut(duration: trans)
        }
    }

    var snap: Animation {
        let d: Double = switch motion {
        case .slam: 0.62
        case .pop: 0.66
        case .rise: 0.74
        case .drift: 0.86
        case .fade: 0.8
        }
        return .spring(response: min(max(trans * 0.9, 0.24), 0.48), dampingFraction: d)
    }

    var enter: AnyTransition {
        let ins: AnyTransition, out: AnyTransition
        switch motion {
        case .slam:
            ins = .scale(scale: 1.3).combined(with: .opacity)
            out = .scale(scale: 0.85).combined(with: .opacity)
        case .pop:
            ins = .scale(scale: 0.75).combined(with: .opacity)
            out = .scale(scale: 1.1).combined(with: .opacity)
        case .rise:
            ins = .offset(y: 28).combined(with: .opacity)
            out = .offset(y: -28).combined(with: .opacity)
        case .drift:
            ins = .offset(y: 12).combined(with: .opacity)
            out = .offset(y: -12).combined(with: .opacity)
        case .fade:
            ins = .opacity
            out = .opacity
        }
        return .asymmetric(insertion: ins.animation(anim.delay(trans * 0.35)), removal: out.animation(.easeOut(duration: trans * 0.6)))
    }
}

struct LyricsFrame {
    let pos: TimeInterval
    let idx: Int?
    let prog: Double
    let words: [Double]
    let gap: Bool
    let level: Double
    let beat: Double

    @MainActor init(_ m: LyricsModel, at now: Date) {
        let p = m.position(at: now) ?? 0
        pos = p
        let tl = m.timeline
        let i = tl?.index(at: p)
        idx = i
        if let tl, let i {
            prog = tl.progress(of: i, at: p)
            words = tl.lyrics.lines[i].w.isEmpty ? [] : tl.wordProgress(line: i, at: p)
            gap = tl.isInstrumentalGap(at: p)
        } else {
            prog = 0
            words = []
            gap = tl.map { $0.isInstrumentalGap(at: p) } ?? false
        }
        let v = m.pulse.value
        let live = m.settings.settings.lyrics.livePulse && (m.media.nowPlaying?.isPlaying ?? false)
        level = live ? v.level : 0
        beat = live ? v.beat : 0
    }
}

struct LyricsLineText: View {
    let line: LyricLine
    let style: LyricsStyle
    let size: CGFloat
    let active: Bool
    let prog: Double
    let words: [Double]
    let lit: Color
    let dim: Color
    var morph = false

    var body: some View {
        let s = style.upper ? line.s.uppercased() : line.s
        Group {
            if active || morph {
                fill(s)
            } else {
                Text(s).foregroundStyle(dim)
            }
        }
        .font(style.font(size, active: active || morph))
        .tracking(style.tracking * size)
    }

    private func fill(_ s: String) -> Text {
        if style.fill == false { return Text(s).foregroundStyle(lit) }
        let parts: [(String, Double)]
        if !line.w.isEmpty, words.count == line.w.count {
            parts = zip(line.w, words).map { (style.upper ? $0.0.s.uppercased() : $0.0.s, $0.1) }
        } else {
            let ws = s.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            let total = Double(max(s.count, 1))
            var acc = 0.0
            parts = ws.enumerated().map { k, w in
                let a = acc / total
                acc += Double(w.count + 1)
                let b = acc / total
                let p = b > a ? min(max((prog - a) / (b - a), 0), 1) : 1
                return (k + 1 < ws.count ? w + " " : w, p)
            }
        }
        var t = Text("")
        for (w, p) in parts {
            t = t + Text(w).foregroundStyle(dim.mix(with: lit, by: p))
        }
        return t
    }
}

struct LyricsScroller: View {
    let model: LyricsModel
    var base: CGFloat = 26
    var center = false
    var interactive = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(paused: !(model.media.nowPlaying?.isPlaying ?? false))) { ctx in
            let f = LyricsFrame(model, at: ctx.date)
            content(f)
        }
    }

    @ViewBuilder private func content(_ f: LyricsFrame) -> some View {
        let st = model.style
        let lit: Color = scheme == .dark ? .white : .black
        let dim = lit.opacity(0.32)
        if let tl = model.timeline, tl.lyrics.synced {
            ScrollViewReader { r in
                ScrollView(.vertical) {
                    VStack(alignment: center ? .center : .leading, spacing: base * 0.55) {
                        Color.clear.frame(height: base * 3)
                        ForEach(Array(tl.lyrics.lines.enumerated()), id: \.offset) { k, l in
                            row(k, l, f, st, lit, dim)
                                .id(k)
                        }
                        Color.clear.frame(height: base * 6)
                    }
                    .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
                    .padding(.horizontal, base * 0.8)
                }
                .scrollIndicators(.never)
                .scrollDisabled(!interactive)
                .onChange(of: f.idx, initial: true) { _, i in
                    guard let i else { return }
                    withAnimation(st.anim) { r.scrollTo(i, anchor: UnitPoint(x: 0.5, y: 0.36)) }
                }
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                                         .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        } else if let l = model.lyrics, !l.lines.isEmpty {
            ScrollView {
                Text(l.lines.map(\.s).joined(separator: "\n"))
                    .font(st.font(base * 0.7, active: false))
                    .foregroundStyle(lit.opacity(0.8))
                    .multilineTextAlignment(center ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
                    .padding(base * 0.8)
            }
            .scrollIndicators(.never)
        } else {
            LyricsEmpty(model: model, base: base)
        }
    }

    @ViewBuilder private func row(_ k: Int, _ l: LyricLine, _ f: LyricsFrame, _ st: LyricsStyle,
                                  _ lit: Color, _ dim: Color) -> some View {
        let act = k == f.idx && !(f.gap && l.isBreak)
        let dist = f.idx.map { abs(k - $0) } ?? 3
        let sc = act ? 1 + f.beat * st.pulse * 0.05 : 1
        let shake = act ? sin(f.pos * 90) * f.beat * st.shake * 2.5 : 0
        Group {
            if l.isBreak {
                LyricsBreakDots(prog: act ? f.prog : 0, lit: lit, dim: dim, size: base * 0.5)
                    .frame(height: base)
            } else {
                LyricsLineText(line: l, style: st, size: base, active: act, prog: f.prog, words: act ? f.words : [],
                               lit: lit, dim: dim)
                    .multilineTextAlignment(center ? .center : .leading)
            }
        }
        .scaleEffect(act ? sc : 0.94, anchor: center ? .center : .leading)
        .offset(x: shake)
        .blur(radius: act ? 0 : min(Double(dist), 3) * st.blur * 0.5)
        .opacity(act ? 1 : max(0.25, 1 - Double(dist) * 0.18))
        .animation(st.anim, value: act)
        .contentShape(Rectangle())
        .onTapGesture { if interactive { model.seek(to: l.t) } }
    }
}

struct LyricsBreakDots: View {
    let prog: Double
    let lit: Color
    let dim: Color
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.5) {
            ForEach(0..<3, id: \.self) { k in
                let p = min(max(prog * 3 - Double(k), 0), 1)
                Circle().fill(dim.mix(with: lit, by: p)).frame(width: size * 0.6, height: size * 0.6)
                    .scaleEffect(0.8 + p * 0.3)
            }
        }
    }
}

struct LyricsEmpty: View {
    let model: LyricsModel
    let base: CGFloat
    @Environment(\.shellStyle) private var style

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: base * 1.1, weight: .light)).foregroundStyle(.secondary)
            Text(text).font(style.font(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            if model.phase == .failed {
                Button("Try Again") { model.retry() }.buttonStyle(.borderless).font(style.font(size: 12, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: String {
        switch model.phase {
        case .off: "quote.bubble"
        case .loading: "ellipsis"
        case .failed: "wifi.exclamationmark"
        case .ready where model.lyrics?.instrumental == true: "music.note"
        default: "text.badge.xmark"
        }
    }

    private var text: String {
        switch model.phase {
        case .off: String(localized: "Turn on Lyrics in Nexus")
        case .idle: String(localized: "Nothing is playing")
        case .loading: String(localized: "Loading Lyrics…")
        case .failed: String(localized: "Lyrics Unavailable")
        case .ready where model.lyrics?.instrumental == true: String(localized: "Instrumental")
        default: String(localized: "No Lyrics Found")
        }
    }
}

struct LyricsOffsetControl: View {
    let model: LyricsModel
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack(spacing: 4) {
            Button { model.nudge(-LyricsOffsets.step) } label: { Image(systemName: "minus") }
            Text(label).monospacedDigit().frame(minWidth: 46)
            Button { model.nudge(LyricsOffsets.step) } label: { Image(systemName: "plus") }
        }
        .buttonStyle(.borderless)
        .font(style.font(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .help(String(localized: "Lyrics earlier or later for this song"))
    }

    private var label: String {
        let v = model.userOffset
        if abs(v) < 0.001 { return model.autoOffset != nil ? "auto" : "0.0 s" }
        return String(format: "%+.1f s", v)
    }
}

struct LyricsCard: View {
    let model: MediaModel
    let size: CGSize

    var body: some View {
        Card(radius: 28) {
            if let l = model.lyrics {
                ZStack(alignment: .topTrailing) {
                    LyricsScroller(model: l, base: size.height < 320 ? 20 : 26)
                    if l.timeline?.lyrics.synced == true {
                        LyricsOffsetControl(model: l).padding(12)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                Text("Lyrics").foregroundStyle(.secondary)
            }
        }
        .onAppear { model.lyrics?.acquire() }
        .onDisappear { model.lyrics?.release() }
    }
}
