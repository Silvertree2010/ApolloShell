import Foundation
import ApolloShellCore
import Observation

// Die Reiter (`DashboardTab`) stehen in ApolloShellCore/DashboardLayout.swift:
// Nexus ordnet und blendet sie, settings.json nennt sie beim Namen.

/// Zustand des Dashboards: Reiter, Uhr, Kalendermonat, Ressourcen.
/// Misst nur, solange es offen ist (`start`/`stop`).
@MainActor
@Observable
final class DashboardModel {
    var tab: DashboardTab = .dashboard {
        didSet { syncPerformance() }
    }
    /// Reiter "Leistung"; misst nur bei offenem Dashboard und sichtbarem Reiter.
    let performance = PerformanceModel()
    private(set) var now = Date()
    private(set) var cpu: Double = 0
    private(set) var memory: Double = 0
    private(set) var storage: Double = 0
    /// Welcher Monat im Kalender angezeigt wird (Pfeile blaettern).
    private(set) var shownMonth = Date()

    private(set) var userName = NSFullUserName()
    let systemVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }()
    let machineName = Host.current().localizedName ?? "Mac"

    /// Montag zuerst; Wochentage in der gewaehlten Sprache (Nexus > Allgemein).
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        calendar.firstWeekday = 2
        return calendar
    }()

    var uptime: String { UptimeText.format(seconds: fixedUptime ?? ProcessInfo.processInfo.systemUptime) }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTicks: CPUTicks?
    @ObservationIgnored private var isOpen = false
    /// Feste Laufzeit fuer Bildproben; `nil` = die echte.
    @ObservationIgnored private var fixedUptime: TimeInterval?

    /// Feste Werte fuer Bildproben und die Vorschau in Nexus. Misst nichts,
    /// solange niemand `start` ruft - und das tut nur das echte Dashboard.
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
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        syncPerformance()
    }

    func stop() {
        isOpen = false
        timer?.invalidate()
        timer = nil
        syncPerformance()
    }

    /// Die Leistungs-Messung (GPU, Netzwerk, Verlaeufe) laeuft nur, wenn man
    /// sie sieht: Dashboard offen und Reiter "Leistung" gewaehlt. Ueber das
    /// Modell statt onAppear/onDisappear, weil das Fenster beim Schliessen
    /// nur ausgeblendet wird - die Ansicht verschwindet dabei nicht.
    private func syncPerformance() {
        if isOpen && tab == .performance {
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
