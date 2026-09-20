import Foundation
import ApolloShellCore
import Observation

// The tabs (`DashboardTab`) stand in ApolloShellCore/DashboardLayout.swift:
// Nexus orders and hides them, settings.json names them.

/// The state of the dashboard: the tabs, the clock, the calendar month, the
/// resources. It only measures while it is open (`start`/`stop`).
@MainActor
@Observable
final class DashboardModel {
    /// The open page; `nil`: the first one (migration/default).
    var pageID: DashboardPage.ID?
    /// Whether the open page shows a performance widget - `Dashboard` sets it
    /// on opening and on every page change.
    var showsPerformance = false {
        didSet { syncPerformance() }
    }
    /// Measures only with the dashboard open and a page with a performance widget.
    let performance = PerformanceModel()
    /// The scale for the screen (`Dashboard.prepareForScreen`); 1 is the
    /// reference size (`BentoGeometry`).
    var scale: CGFloat = 1
    private(set) var now = Date()
    private(set) var cpu: Double = 0
    private(set) var memory: Double = 0
    private(set) var storage: Double = 0
    /// Which month is shown in the calendar (the arrows page through).
    private(set) var shownMonth = Date()

    private(set) var userName = NSFullUserName()
    let systemVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }()
    let machineName = Host.current().localizedName ?? "Mac"

    /// Monday first; the weekdays in the chosen language (Nexus > General).
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        calendar.firstWeekday = 2
        return calendar
    }()

    var uptime: String { UptimeText.format(seconds: fixedUptime ?? ProcessInfo.processInfo.systemUptime) }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTicks: CPUTicks?
    /// Whether the window is open right now (or pinned for editing) -
    /// `DashboardView` reads it to restart weather models only then.
    @ObservationIgnored private(set) var isOpen = false
    /// A fixed uptime for image samples; `nil` = the real one.
    @ObservationIgnored private var fixedUptime: TimeInterval?

    /// Fixed values for image samples and the preview in Nexus. It measures
    /// nothing while nobody calls `start` - and only the real dashboard does that.
    static func preview(now: Date, cpu: Double, memory: Double, storage: Double,
                        userName: String, uptime: TimeInterval) -> DashboardModel {
        let model = DashboardModel()
        model.now = now
        model.shownMonth = now
        model.cpu = cpu
        model.memory = memory
        model.storage = storage
        model.userName = userName
        model.fixedUptime = uptime
        return model
    }

    func start() {
        isOpen = true
        shownMonth = now
        refresh()
        timer?.invalidate()
        timer = .repeating(every: 1, owner: self) { $0.refresh() }
        syncPerformance()
    }

    func stop() {
        isOpen = false
        timer?.invalidate()
        timer = nil
        syncPerformance()
    }

    /// The performance measuring (GPU, network, the histories) only runs when
    /// one sees it: the dashboard open and the "Performance" tab chosen.
    /// Through the model instead of onAppear/onDisappear, because the window is
    /// only hidden on closing - the view does not disappear with it.
    private func syncPerformance() {
        if isOpen && showsPerformance {
            performance.start()
        } else {
            performance.stop()
        }
    }

    func showMonth(offset: Int) {
        shownMonth = calendar.date(byAdding: .month, value: offset, to: shownMonth) ?? shownMonth
    }

    private func refresh() {
        now = Date()
        if let ticks = SystemSampler.cpuTicks() {
            if let old = lastTicks, let usage = ResourceMath.cpuUsage(from: old, to: ticks) {
                cpu = usage
            }
            lastTicks = ticks
        }
        if let m = SystemSampler.memory() { memory = ResourceMath.fraction(used: m.used, total: m.total) }
        if let s = SystemSampler.storage() { storage = ResourceMath.fraction(used: s.used, total: s.total) }
    }
}
