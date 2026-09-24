import ApolloShellCore
import SwiftUI

/// The shell's one timer (`ShellTimer.shared`, the same as the dashboard
/// widget and the bar block) in the control centre: a small ring with the
/// time, quick starts while it is idle, pause and reset while it runs.
struct UtilitiesTimerCard: View {
    let timer: ShellTimer
    @Environment(\.shellStyle) private var style

    private static let presets = [5, 15, 25]

    var body: some View {
        let state = timer.state
        UtilitiesCard {
            TimelineView(.animation(minimumInterval: 1, paused: !state.isRunning || timer.fixedNow != nil)) { context in
                let now = timer.fixedNow ?? context.date
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.10), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: state.mode == .stopwatch ? state.progress(at: now) : 1 - state.progress(at: now))
                            .stroke(style.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "timer").font(style.font(size: 16, weight: .semibold))
                    }
                    .frame(width: 44, height: 44)
                    Text(TimerCard.text(state, now: now))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if state.isIdle {
                        ForEach(Self.presets, id: \.self) { minutes in
                            Button {
                                timer.set(mode: .timer, minutes: minutes)
                                timer.prepare(minutes: minutes)
                                timer.toggle()
                            } label: {
                                Text("\(minutes)")
                                    .font(style.font(size: 13, weight: .semibold))
                                    .frame(width: 36, height: 30)
                                    .background(Color.primary.opacity(0.08), in: .capsule)
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "Start \(minutes) Minutes"))
                        }
                    } else {
                        Button { timer.reset() } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(style.font(size: 12, weight: .semibold))
                                .frame(width: 30, height: 30)
                                .background(Color.primary.opacity(0.08), in: .circle)
                        }
                        .buttonStyle(.plain)
                        .help("Reset")
                        Button { timer.toggle() } label: {
                            Image(systemName: state.isRunning ? "pause.fill" : "play.fill")
                                .font(style.font(size: 13, weight: .semibold))
                                .foregroundStyle(style.onAccent)
                                .frame(width: 48, height: 30)
                                .background(style.accent, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .help(state.isRunning ? "Pause" : "Start")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timer")
    }
}
