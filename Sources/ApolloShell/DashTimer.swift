import AppKit
import ApolloShellCore
import SwiftUI

@MainActor
@Observable
final class DashTimer {
    static let shared = DashTimer()

    enum Mode: String, CaseIterable { case timer, stopwatch }

    var mode: Mode = .timer
    private(set) var running = false
    private(set) var total: TimeInterval = 25 * 60
    private(set) var elapsed: TimeInterval = 0
    private(set) var now = Date()
    @ObservationIgnored private var started: Date?
    @ObservationIgnored private var tick: Timer?
    @ObservationIgnored var sound = true
    @ObservationIgnored var onDone: (String) -> Void = { _ in }

    var spent: TimeInterval { elapsed + (started.map { now.timeIntervalSince($0) } ?? 0) }
    var remaining: TimeInterval { max(0, total - spent) }
    var shown: TimeInterval { mode == .timer ? remaining : spent }
    var progress: Double { mode == .timer && total > 0 ? min(1, spent / total) : 0 }
    var idle: Bool { !running && elapsed == 0 }

    func set(minutes: Int) {
        guard idle else { return }
        total = TimeInterval(minutes * 60)
    }

    func toggle() { running ? pause() : start() }

    func start() {
        guard !running else { return }
        if mode == .timer, remaining <= 0 { elapsed = 0 }
        running = true
        started = Date()
        now = Date()
        tick = .repeating(every: 0.5, tolerance: 0.1, owner: self) { $0.step() }
    }

    func pause() {
        guard running else { return }
        elapsed = spent
        started = nil
        running = false
        tick?.invalidate()
        tick = nil
    }

    func reset() {
        pause()
        elapsed = 0
        now = Date()
    }

    private func step() {
        now = Date()
        guard mode == .timer, remaining <= 0 else { return }
        reset()
        if sound { NSSound(named: "Glass")?.play() }
        onDone(Self.text(total))
    }

    static func text(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}

struct TimerCard: View {
    let options: DashboardTimerOptions
    let vertical: Bool
    @State private var t = DashTimer.shared
    @Environment(\.shellStyle) private var style

    var body: some View {
        Card(radius: 16) {
            VStack(spacing: 10) {
                Picker("", selection: Binding(get: { t.mode }, set: { m in t.reset(); t.mode = m })) {
                    Image(systemName: "timer").tag(DashTimer.Mode.timer)
                    Image(systemName: "stopwatch").tag(DashTimer.Mode.stopwatch)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 110)
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: t.mode == .timer ? 1 - t.progress : 1)
                        .stroke(style.accentFill, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .opacity(t.mode == .timer ? 1 : (t.running ? 1 : 0.3))
                        .animation(.linear(duration: 0.5), value: t.progress)
                    Text(DashTimer.text(t.shown))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .frame(width: 92, height: 92)
                HStack(spacing: 8) {
                    if t.mode == .timer && t.idle {
                        ForEach([5, 15, options.minutes], id: \.self) { m in
                            Button("\(m)") { t.set(minutes: m) }
                                .buttonStyle(.plain)
                                .font(style.font(size: 11, weight: .semibold))
                                .frame(width: 26, height: 22)
                                .background(Color.primary.opacity(Int(t.total / 60) == m ? 0.18 : 0.08), in: .capsule)
                        }
                    } else {
                        Button { t.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                            .buttonStyle(.plain)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.08), in: .circle)
                    }
                    Button { t.toggle() } label: { Image(systemName: t.running ? "pause.fill" : "play.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(style.color(.onAccent) ?? .white)
                        .frame(width: 28, height: 28)
                        .background(style.accentFill, in: .circle)
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .onAppear { t.sound = options.sound; t.set(minutes: options.minutes) }
        }
    }
}
