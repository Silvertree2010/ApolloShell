import Foundation
import ApolloShellCore
import Observation

/// Belegt/gesamt in Byte (Arbeitsspeicher, Festplatte).
struct ByteUsage: Equatable {
    var used: UInt64
    var total: UInt64

    var fraction: Double { ResourceMath.fraction(used: used, total: total) }
}

/// Messwerte fuer den Reiter "Leistung" (Caelestia: Performance).
///
/// Misst im Sekundentakt, aber nur, solange das Dashboard offen UND dieser
/// Reiter sichtbar ist (`DashboardModel` schaltet `start`/`stop`) - die
/// restliche Zeit kostet er nichts.
@MainActor
@Observable
final class PerformanceModel {
    /// Caelestia: Verlauf der letzten 30 Messungen, eine pro Sekunde.
    static let historyLength = 30
    static let interval: TimeInterval = 1

    /// Ohne Wert (`nil`) zeigen die Karten einen Strich statt einer falschen Null.
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
    /// `nil` auf Macs ohne Akku: dann faellt der Tank weg.
    private(set) var battery: BatteryState?
    private(set) var batteryMinutes: Int?

    let cpuSubtitle = String(localized: "\(PerformanceSampler.chipName) · \(ProcessInfo.processInfo.activeProcessorCount) Kerne")
    let gpuSubtitle = PerformanceSampler.gpuCores.map { String(localized: "\(PerformanceSampler.chipName) · \($0) Kerne") }
        ?? PerformanceSampler.chipName

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTicks: CPUTicks?
    @ObservationIgnored private var meter = NetworkMeter()

    /// Eine Messung, getrennt vom Lesen: so bekommt die Ansicht im
    /// Render-Test feste Beispielwerte statt der echten.
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

    /// Laeuft die Sekundenmessung gerade?
    var isSampling: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        // Neu anfangen: CPU- und Netzwerkraten ueber die Pause gemittelt
        // waeren falsch, und die Linien sollen lueckenlose Sekunden zeigen.
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
        // Schlaegt eine Abfrage einmal fehl, bleibt der letzte Wert stehen.
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
        // Nur bei Aenderung setzen: sonst zeichnet der Tank jede Sekunde neu.
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
