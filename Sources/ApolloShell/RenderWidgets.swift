import AppKit
import ApolloShellCore
import SwiftUI

/// `ApolloShell --render-widgets <folder> [<kind>...]`: one contact sheet per
/// widget kind (`<kind>-dark.png`, `<kind>-light.png`) - every display mode
/// in a row, every size of the catalogue at its smallest and its widest
/// width (capped at 560, wider only shows more of the same). With sample
/// data for everything, performance histories and a cover included, so that
/// no size gets judged by its empty state. Draws offscreen like
/// `--render-dashboard` and touches nothing of a running shell.
@MainActor
enum RenderWidgets {
    static func run(into folder: URL, kinds: [WidgetKind]) throws {
        let fixtures = RenderFixtures()
        fillPerformance(fixtures.dashboard.performance)
        let place = WeatherLocation(name: "Berlin", latitude: 52.52, longitude: 13.405)
        let media = MediaModel.preview(
            nowPlaying: MediaNowPlaying(title: "Sample Track", artist: "Sample Band", album: "Sample Album",
                                        isPlaying: true, duration: 240, elapsed: 80, timestamp: fixtures.now,
                                        playbackRate: 1),
            artwork: sampleCover(), source: MediaSource(name: "Music", icon: nil), now: fixtures.now)
        let context = WidgetContext(dashboard: fixtures.dashboard, media: media, weather: { _ in fixtures.weather })
        for kind in kinds.isEmpty ? WidgetKind.allCases : kinds {
            let sheet = VStack(alignment: .leading, spacing: 18) {
                ForEach(kind.displays, id: \.self) { display in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(kind.rawValue) · \(display.rawValue)").font(.system(size: 12, weight: .semibold))
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(Array(frames(kind).enumerated()), id: \.offset) { _, size in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(format(size.width)) × \(format(size.height))")
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                    WidgetView(widget: WidgetInstance(
                                        kind: kind, frame: WidgetFrame(x: 0, y: 0, width: size.width, height: size.height),
                                        options: options(kind, display: display, place: place)), context: context)
                                        .frame(width: size.width, height: size.height)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
            for scheme in [ColorScheme.dark, .light] {
                try RenderMode.write(sheet, scheme: scheme,
                                     to: folder.appendingPathComponent(RenderMode.name(kind.rawValue, scheme)))
            }
        }
    }

    private static func frames(_ kind: WidgetKind) -> [CGSize] {
        var result: [CGSize] = []
        for size in kind.sizes {
            result.append(CGSize(width: size.minWidth, height: size.height))
            let wide = min(size.maxWidth, 560)
            if wide > size.minWidth + 40 { result.append(CGSize(width: wide, height: size.height)) }
        }
        return result
    }

    private static func options(_ kind: WidgetKind, display: WidgetDisplay, place: WeatherLocation) -> WidgetOptions {
        var options = WidgetOptions.defaults(for: kind,
                                             places: WeatherFavorites(locations: [place], selectedID: place.id))
        options.display = display
        return options
    }

    private static func format(_ value: CGFloat) -> String {
        value == value.rounded() ? "\(Int(value))" : "\(value)"
    }

    /// Thirty seconds of made-up but plausible readings: CPU and GPU waves,
    /// a download burst, a steady upload, a battery at two thirds.
    static func fillPerformance(_ model: PerformanceModel) {
        var ticks = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        var counters = NetCounters.zero
        for second in 0...PerformanceModel.historyLength {
            let t = Double(second)
            let cpu = 0.28 + 0.18 * sin(t / 3) + (second % 7 == 0 ? 0.2 : 0)
            ticks.user += UInt64(cpu * 700)
            ticks.system += UInt64(cpu * 300)
            ticks.idle += UInt64((1 - cpu) * 1000)
            counters.received += UInt64(second > 18 && second < 26 ? 2_400_000 : 180_000 + 60_000 * (second % 4))
            counters.sent += UInt64(90_000 + 30_000 * (second % 3))
            model.ingest(PerformanceModel.Sample(
                time: t, cpuTicks: ticks, gpu: 0.35 + 0.25 * cos(t / 4),
                memory: ByteUsage(used: 15_800_000_000, total: 25_769_803_776),
                storage: ByteUsage(used: 412_000_000_000, total: 994_662_584_320),
                network: counters, battery: BatteryState(level: 67, charging: false, onAC: false),
                batteryMinutes: 254))
        }
    }

    /// A made-up cover: a diagonal sunset gradient with a pale disc, so the
    /// player's background has real colour to work with.
    static func sampleCover() -> NSImage {
        let size = NSSize(width: 600, height: 600)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.95, green: 0.45, blue: 0.25, alpha: 1),
                                NSColor(red: 0.55, green: 0.18, blue: 0.55, alpha: 1),
                                NSColor(red: 0.12, green: 0.10, blue: 0.35, alpha: 1)])?
                .draw(in: rect, angle: -45)
            NSColor(white: 1, alpha: 0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: 330, y: 330, width: 150, height: 150)).fill()
            return true
        }
    }
}
