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
        Group {
            switch widget.kind {
            case .weather:
                SmallWeatherCard(model: context.weather(widget), options: widget.options.weather ?? .init(),
                                 vertical: upright)
            case .user:
                UserCard(model: context.dashboard, options: widget.options.user ?? .init(), vertical: upright)
            case .clock:
                DateTimeCard(now: context.dashboard.now, locale: context.dashboard.calendar.locale ?? .current,
                            options: widget.options.clock ?? .init())
            case .calendar:
                CalendarCard(model: context.dashboard, options: widget.options.calendar ?? .init(),
                            tall: size.height > 300)
            case .resources:
                ResourcesCard(model: context.dashboard, options: widget.options.resources ?? .init(),
                              horizontal: size.width > size.height)
            case .media:
                let options = widget.options.media ?? .init()
                // Right (200 x 392) Caelestia's card; flat and wide a
                // strip; otherwise the small portrait one.
                if size.width > size.height * 1.3 {
                    MediaStripCard(model: context.media, options: options, height: size.height)
                } else if size.height >= 330 {
                    MediaDashCard(model: context.media, options: options)
                } else {
                    MediaCompactCard(model: context.media, options: options)
                }
            case .performanceCPU:
                let model = context.dashboard.performance
                HeroCard(symbol: "cpu", iconID: "panel-cpu", title: "CPU", subtitle: model.cpuSubtitle,
                        value: model.cpu, history: model.cpuHistory)
            case .performanceGPU:
                let model = context.dashboard.performance
                HeroCard(symbol: "square.stack.3d.up", title: "GPU", subtitle: model.gpuSubtitle,
                        value: model.gpu, history: model.gpuHistory)
            case .performanceStorage:
                StorageCard(usage: context.dashboard.performance.storage)
            case .performanceNetwork:
                NetworkCard(model: context.dashboard.performance)
            case .performanceMemory:
                MemoryCard(usage: context.dashboard.performance.memory)
            case .performanceBattery:
                if let battery = context.dashboard.performance.battery {
                    BatteryTank(state: battery, minutes: context.dashboard.performance.batteryMinutes)
                }
            case .weatherHero:
                let model = context.weather(widget)
                // "Now" ticks along every minute (sun position, "As of HH:MM"),
                // not only on new data.
                TimelineView(.everyMinute) { context in
                    let now = model.fixedNow ?? context.date
                    if let report = model.report {
                        WeatherHero(report: report, model: model, now: now, stand: model.standText(now: now))
                    } else {
                        WeatherEmptyState(model: model)
                    }
                }
            case .weatherHourly:
                let model = context.weather(widget)
                TimelineView(.everyMinute) { context in
                    let now = model.fixedNow ?? context.date
                    if let report = model.report {
                        WeatherHourly(slots: report.hourlyStrip(now: now), calendar: report.calendar)
                    } else {
                        WeatherEmptyState(model: model)
                    }
                }
            case .weatherDaily:
                let model = context.weather(widget)
                TimelineView(.everyMinute) { context in
                    let now = model.fixedNow ?? context.date
                    if let report = model.report {
                        WeatherDaily(days: report.upcomingDays(now: now), now: now, calendar: report.calendar)
                    } else {
                        WeatherEmptyState(model: model)
                    }
                }
            case .mediaPlayer:
                MediaTab(model: context.media)
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
