import ApolloShellCore
import SwiftUI

/// A widget in its frame - the one place where every kind gets its
/// view. Size is set by the page (`BentoPageView`); the
/// shape follows the area like before 0.2 (portrait, tall, wide).
struct WidgetView: View {
    let widget: WidgetInstance
    let context: WidgetContext

    var body: some View {
        let size = CGSize(width: widget.frame.width, height: widget.frame.height)
        // Portrait: tall enough for symbol above text, too narrow for side by side.
        let upright = size.height >= 200 && size.width < 300
        let display = widget.options.display(for: widget.kind)
        Group {
            switch widget.kind {
            case .weather:
                SmallWeatherCard(model: context.weather(widget), options: widget.options.weather ?? .init(),
                                 vertical: upright, minimal: display == .minimal)
            case .user:
                if display == .minimal {
                    UserMinimalCard(model: context.dashboard, size: size)
                } else {
                    UserCard(model: context.dashboard, options: widget.options.user ?? .init(), vertical: upright)
                }
            case .clock:
                if display == .analog {
                    AnalogClockCard(now: context.dashboard.now, locale: context.dashboard.calendar.locale ?? .current,
                                    options: widget.options.clock ?? .init(), size: size)
                } else {
                    DateTimeCard(now: context.dashboard.now, locale: context.dashboard.calendar.locale ?? .current,
                                options: widget.options.clock ?? .init(), size: size)
                }
            case .calendar:
                if display == .today {
                    CalendarTodayCard(model: context.dashboard, size: size)
                } else {
                    CalendarCard(model: context.dashboard, options: widget.options.calendar ?? .init(),
                                tall: size.height > 300)
                }
            case .resources:
                if display == .bars {
                    ResourcesBarsCard(model: context.dashboard, options: widget.options.resources ?? .init(), size: size)
                } else {
                    ResourcesCard(model: context.dashboard, options: widget.options.resources ?? .init(),
                                  horizontal: size.width > size.height, size: size)
                }
            case .media:
                let options = widget.options.media ?? .init()
                // Right (200 x 392) Caelestia's card; flat and wide a
                // strip; otherwise the small portrait one.
                if display == .cover {
                    MediaCoverCard(model: context.media, size: size)
                } else if size.width > size.height * 1.3 {
                    MediaStripCard(model: context.media, options: options, height: size.height, width: size.width)
                } else if size.height >= 330 {
                    MediaDashCard(model: context.media, options: options)
                } else {
                    MediaCompactCard(model: context.media, options: options)
                }
            case .performanceCPU, .performanceGPU:
                let model = context.dashboard.performance
                let cpu = widget.kind == .performanceCPU
                let symbol = cpu ? "cpu" : "square.stack.3d.up"
                let iconID = cpu ? "panel-cpu" : ""
                let title = cpu ? "CPU" : "GPU"
                let subtitle = cpu ? model.cpuSubtitle : model.gpuSubtitle
                let value = cpu ? model.cpu : model.gpu
                let history = cpu ? model.cpuHistory : model.gpuHistory
                switch display {
                case .graph:
                    HeroGraphCard(symbol: symbol, iconID: iconID, title: title, subtitle: subtitle,
                                  value: value, history: history)
                case .gauge:
                    HeroGaugeCard(symbol: symbol, iconID: iconID, title: title, subtitle: subtitle,
                                  value: value, size: size)
                default:
                    HeroCard(symbol: symbol, iconID: iconID, title: title, subtitle: subtitle,
                             value: value, history: history, height: size.height)
                }
            case .performanceStorage:
                let usage = context.dashboard.performance.storage
                if display == .bar {
                    UsageBarCard(title: "Storage", iconID: "panel-disk", symbol: "internaldrive.fill",
                                 usage: usage, binary: false, size: size)
                } else {
                    StorageCard(usage: usage, size: size)
                }
            case .performanceNetwork:
                if display == .numbers {
                    NetworkNumbersCard(model: context.dashboard.performance, size: size)
                } else {
                    NetworkCard(model: context.dashboard.performance, height: size.height)
                }
            case .performanceMemory:
                let usage = context.dashboard.performance.memory
                if display == .bar {
                    // Binary like Activity Monitor: 24 GB of RAM stay 24 GB.
                    UsageBarCard(title: "Memory", iconID: "panel-memory", symbol: "memorychip.fill",
                                 usage: usage, binary: true, size: size)
                } else {
                    MemoryCard(usage: usage, size: size)
                }
            case .performanceBattery:
                if let battery = context.dashboard.performance.battery {
                    if display == .ring {
                        BatteryRingCard(state: battery, minutes: context.dashboard.performance.batteryMinutes,
                                        size: size)
                    } else {
                        BatteryTank(state: battery, minutes: context.dashboard.performance.batteryMinutes)
                    }
                }
            case .weatherHero:
                let model = context.weather(widget)
                // "Now" ticks along every minute (sun position, "As of HH:MM"),
                // not only on new data.
                TimelineView(.everyMinute) { context in
                    let now = model.fixedNow ?? context.date
                    if let report = model.report {
                        WeatherHero(report: report, model: model, now: now, stand: model.standText(now: now),
                                    size: size, minimal: display == .minimal)
                    } else {
                        WeatherEmptyState(model: model)
                    }
                }
            case .weatherHourly:
                let model = context.weather(widget)
                TimelineView(.everyMinute) { context in
                    let now = model.fixedNow ?? context.date
                    if let report = model.report {
                        WeatherHourly(slots: report.hourlyStrip(now: now), calendar: report.calendar,
                                      size: size, graph: display == .graph)
                    } else {
                        WeatherEmptyState(model: model)
                    }
                }
            case .weatherDaily:
                let model = context.weather(widget)
                TimelineView(.everyMinute) { context in
                    let now = model.fixedNow ?? context.date
                    if let report = model.report {
                        WeatherDaily(days: report.upcomingDays(now: now), now: now, calendar: report.calendar,
                                     size: size, list: display == .list)
                    } else {
                        WeatherEmptyState(model: model)
                    }
                }
            case .mediaPlayer:
                if display == .cover {
                    MediaCoverCard(model: context.media, size: size)
                } else {
                    MediaTab(model: context.media, size: size)
                }
            }
        }
    }
}

/// Small stand-in display for a weather widget without a report (no location or
/// no data yet) - the same states as `WeatherTab`, just per widget.
private struct WeatherEmptyState: View {
    let model: WeatherModel
    @Environment(\.shellStyle) private var style

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: model.location == nil ? "location.slash" : "cloud.sun")
                .font(style.font(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            if model.location == nil {
                Text("Set a Location under Edit Interface").font(style.font(size: 13, weight: .semibold))
            } else {
                Text(model.lastAttemptFailed ? String(localized: "No Weather Data") : String(localized: "Loading Weather…"))
                    .font(style.font(size: 13, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// What widgets need to draw. Weather comes per widget
/// (`weather(for:)`), because every weather widget has its own locations.
@MainActor
struct WidgetContext {
    let dashboard: DashboardModel
    let media: MediaModel
    let weather: (WidgetInstance) -> WeatherModel
}
