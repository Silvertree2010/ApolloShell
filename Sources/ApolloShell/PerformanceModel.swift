import Foundation
import ApolloShellCore
import Observation

/// Used/total in bytes (memory, disk).
struct ByteUsage: Equatable {
    var used: UInt64
    var total: UInt64

    var fraction: Double { ResourceMath.fraction(used: used, total: total) }
}

/// The readings for the "Performance" tab (Caelestia: Performance).
///
/// It measures every second, but only while the dashboard is open AND this tab
/// is visible (`DashboardModel` switches `start`/`stop`) - the rest of the time
/// it costs nothing.
@MainActor
@Observable
final class PerformanceModel {
    /// Caelestia: the history of the last 30 readings, one per second.
    static let historyLength = 30
    static let interval: TimeInterval = 1

    /// Without a value (`nil`) the cards show a dash instead of a wrong zero.
    private(set) var cpu: Double?
    private(set) var gpu: Double?
    private(set) var memory: ByteUsage?
    private(set) var storage: ByteUsage?
    private(set) var network: NetRate?
    private(set) var networkTotal = NetCounters.zero
    private(set) var cpuHistory = SampleHistory(capacity: PerformanceModel.historyLength)
    private(set) var gpuHistory = SampleHistory(capacity: PerformanceModel.historyLength)
    private(set) var downloadHistory = SampleHistory(capacity: PerformanceModel.historyLength)
    private(set) var uploadHistory = SampleHistory(capacity: PerformanceModel.historyLength)
    /// `nil` on Macs without a battery: then the gauge falls away.
    private(set) var battery: BatteryState?
    private(set) var batteryMinutes: Int?

    let cpuSubtitle = String(localized: "\(PerformanceSampler.chipName) · \(ProcessInfo.processInfo.activeProcessorCount) Cores")
    let gpuSubtitle = PerformanceSampler.gpuCores.map { String(localized: "\(PerformanceSampler.chipName) · \($0) Cores") }
        ?? PerformanceSampler.chipName

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTicks: CPUTicks?
    @ObservationIgnored private var meter = NetworkMeter()

    /// One reading, apart from the reading out: that way the view gets fixed
    /// sample values instead of the real ones in the render test.
    struct Sample {
        var time: TimeInterval
        var cpuTicks: CPUTicks?
        var gpu: Double?
        var memory: ByteUsage?
        var storage: ByteUsage?
        var network: NetCounters?
        var battery: BatteryState?
        var batteryMinutes: Int?
    }

    /// Is the per-second measuring running right now?
    var isSampling: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        // Start over: CPU and network rates averaged across the pause would be
        // wrong, and the lines should show seconds without gaps.
        lastTicks = nil
        cpu = nil
        network = nil
        meter.pause()
        cpuHistory.removeAll()
        gpuHistory.removeAll()
        downloadHistory.removeAll()
        uploadHistory.removeAll()
        refresh()
        timer = .repeating(every: Self.interval, owner: self) { $0.refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func ingest(_ sample: Sample) {
        if let ticks = sample.cpuTicks {
            if let old = lastTicks, let usage = ResourceMath.cpuUsage(from: old, to: ticks) {
                cpu = usage
                cpuHistory.append(usage)
            }
            lastTicks = ticks
        }
        gpu = sample.gpu
        if let gpu = sample.gpu { gpuHistory.append(gpu) }
        // When a query fails once, the last value stays standing.
        if let memory = sample.memory { self.memory = memory }
        if let storage = sample.storage { self.storage = storage }
        if let counters = sample.network {
            meter.add(counters, at: sample.time)
            network = meter.rate
            networkTotal = meter.total
            if let rate = meter.rate {
                downloadHistory.append(rate.download)
                uploadHistory.append(rate.upload)
            }
        }
        // Only set on a change: otherwise the gauge would redraw every second.
        if sample.battery != battery { battery = sample.battery }
        if sample.batteryMinutes != batteryMinutes { batteryMinutes = sample.batteryMinutes }
    }

    private func refresh() {
        let battery = PerformanceSampler.battery()
        ingest(Sample(
            time: ProcessInfo.processInfo.systemUptime,
            cpuTicks: SystemSampler.cpuTicks(),
            gpu: PerformanceSampler.gpuUsage(),
            memory: SystemSampler.memory().map { ByteUsage(used: $0.used, total: $0.total) },
            storage: SystemSampler.storage().map { ByteUsage(used: $0.used, total: $0.total) },
            network: PerformanceSampler.networkCounters(),
            battery: battery?.state,
            batteryMinutes: battery?.minutes
        ))
    }
}
