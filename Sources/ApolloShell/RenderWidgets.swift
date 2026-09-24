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
        // A YouTube video in a browser, as measured 09/23: no media type,
        // a wide 150 x 83 preview, an empty album.
        let video = MediaModel.preview(
            nowPlaying: MediaNowPlaying(title: "Transformers (2007) explained by an idiot in fifteen minutes",
                                        artist: "Sample Channel", bundleIdentifier: "com.vivaldi.Vivaldi",
                                        isPlaying: true, duration: 945, elapsed: 210, timestamp: fixtures.now,
                                        playbackRate: 1),
            artwork: sampleCover(size: NSSize(width: 150, height: 83)),
            source: MediaSource(name: "Vivaldi", icon: nil), now: fixtures.now)
        let extras = previewExtras(now: fixtures.now)
        try renderBar(into: folder, now: fixtures.now)
        for kind in kinds.isEmpty ? WidgetKind.allCases : kinds {
            let rows: [(WidgetDisplay, MediaModel, String)] = kind.displays.flatMap { display in
                kind.usesMedia ? [(display, media, "music"), (display, video, "video")] : [(display, media, "")]
            }
            let sheet = VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let (display, rowMedia, label) = row
                    let context = WidgetContext(dashboard: fixtures.dashboard, media: rowMedia,
                                                weather: { _ in fixtures.weather }, extras: extras)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(kind.rawValue) · \(display.rawValue) \(label)").font(.system(size: 12, weight: .semibold))
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

    /// `--render-widgets <folder> bar`: the timer and network blocks of the
    /// bar, idle and running, at the bar's width.
    static func renderBar(into folder: URL, now: Date) throws {
        let running = previewExtras(now: now).timer
        let idle = ShellTimer.preview({ _ in }, now: now)
        let column = HStack(spacing: 24) {
            ForEach([idle, running], id: \.state.isRunning) { timer in
                VStack(spacing: 8) {
                    BarTimerModule(timer: timer)
                    BarNetworkModule(model: BarNetworkModel(preview: NetRate(download: 1_234_000, upload: 85_000))) {}
                    BarNetworkModule(model: BarNetworkModel(preview: NetRate(download: 23_000_000, upload: 420))) {}
                }
                .frame(width: Sidebar.width)
            }
        }
        .padding(16)
        // Without the AppKit mouse views, which `ImageRenderer` draws as a no-entry sign.
        .environment(\.barPreview, true)
        for scheme in [ColorScheme.dark, .light] {
            try RenderMode.write(column, scheme: scheme, to: folder.appendingPathComponent(RenderMode.name("bar", scheme)))
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

    /// Made-up content for the widgets of 09/23: a timer 3:25 into its ten
    /// minutes, a few copied texts and files, a Wi-Fi, two drives, three
    /// pictures. Nothing of this Mac's own is read.
    static func previewExtras(now: Date) -> DashboardExtras {
        let timer = ShellTimer.preview({ timer in
            timer.set(mode: .timer, minutes: 10)
            timer.toggle()
        }, now: now.addingTimeInterval(-205))
        timer.fixedNow = now
        let files = ["Budget 2026.numbers", "Lehrvertrag.pdf", "Screenshot 2026-09-18.png", "ApolloShell",
                     "Notes.md", "Präsentation.key", "Invoice-0042.pdf", "IMG_4211.heic"]
            .enumerated().map { index, name in
                RecentFile(url: URL(fileURLWithPath: "/private/tmp/\(name)"), name: name,
                           used: now.addingTimeInterval(-Double(index + 1) * 5_400))
            }
        let drives = [
            DriveInfo(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", total: 994_662_584_320,
                      free: 582_000_000_000, ejectable: false),
            DriveInfo(url: URL(fileURLWithPath: "/Volumes/Backup"), name: "Backup", total: 2_000_000_000_000,
                      free: 310_000_000_000, ejectable: true),
            DriveInfo(url: URL(fileURLWithPath: "/Volumes/USB"), name: "USB Stick", total: 64_000_000_000,
                      free: 51_000_000_000, ejectable: true),
        ]
        let pictures = [(0.95, 0.45, 0.25), (0.20, 0.55, 0.85), (0.25, 0.70, 0.45)].map { tone in
            NSImage(size: NSSize(width: 800, height: 600), flipped: false) { rect in
                NSGradient(colors: [NSColor(red: tone.0, green: tone.1, blue: tone.2, alpha: 1),
                                    NSColor(red: tone.0 * 0.3, green: tone.1 * 0.3, blue: tone.2 * 0.5, alpha: 1)])?
                    .draw(in: rect, angle: -60)
                return true
            }
        }
        return DashboardExtras(
            timer: timer,
            clipboard: .preview(["git push --force-with-lease origin release/0.2", "Treffen am Freitag um 14:00?",
                                 "https://github.com/silvertree2010/apolloshell", "#3A302A", "Bad Ragaz"]),
            files: .preview(files),
            network: .preview(link: .wifi("Apollo 5G"), local: "192.168.1.42", public: "203.0.113.7", latency: 14),
            drives: .preview(drives),
            photos: .preview(folder: PhotoFrames.defaultFolder, images: pictures))
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
    static func sampleCover(size: NSSize = NSSize(width: 600, height: 600)) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.95, green: 0.45, blue: 0.25, alpha: 1),
                                NSColor(red: 0.55, green: 0.18, blue: 0.55, alpha: 1),
                                NSColor(red: 0.12, green: 0.10, blue: 0.35, alpha: 1)])?
                .draw(in: rect, angle: -45)
            NSColor(white: 1, alpha: 0.85).setFill()
            let disc = min(rect.width, rect.height) * 0.25
            NSBezierPath(ovalIn: NSRect(x: rect.width * 0.55, y: rect.height * 0.55, width: disc, height: disc)).fill()
            return true
        }
    }
}
