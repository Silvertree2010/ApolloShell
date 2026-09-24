import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class PerfProvider: BaseProvider {
    static let barInterval: Double = 2
    static let liveInterval: Double = 1
    static let historyLength = 30
    static let barFields = ["cpu", "memory", "net-down", "net-up"]

    private struct Tier {
        var lastTicks: CPUTicks?
        var meter = NetworkMeter()
        var busy = false
        var generation = 0

        mutating func pause() {
            lastTicks = nil
            meter.pause()
            busy = false
            generation += 1
        }
    }

    private let source: any PerfSource
    private var bar = Tier()
    private var live = Tier()
    private var liveActive = false
    private var cpuHistory = SampleHistory(capacity: PerfProvider.historyLength)
    private var gpuHistory = SampleHistory(capacity: PerfProvider.historyLength)
    private var downHistory = SampleHistory(capacity: PerfProvider.historyLength)
    private var upHistory = SampleHistory(capacity: PerfProvider.historyLength)

    public init(source: any PerfSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("perf"), clock: clock)
    }

    override func didStart() {
        publish("chip", .string(source.chip))
        publish("cores", .number(Double(source.cores)))
        publish("gpu-cores", ProviderValue.number(source.gpuCores))
    }

    override func didChangeDemand() {
        let wantsBar = demand.wantsAny(Self.barFields)
        if !wantsBar, timers.isActive("bar") { bar.pause() }
        timers.set("bar", every: Self.barInterval, active: wantsBar, immediately: true) { [weak self] in
            self?.sampleBar()
        }
        let wantsLive = demand.wants("live")
        if wantsLive && !liveActive { beginLive() }
        if !wantsLive && liveActive { live.pause() }
        liveActive = wantsLive
        timers.set("live", every: Self.liveInterval, active: wantsLive, immediately: true) { [weak self] in
            self?.sampleLive()
        }
    }

    override func didStop() {
        bar.pause()
        live.pause()
        liveActive = false
    }

    private func beginLive() {
        live.pause()
        cpuHistory.removeAll()
        gpuHistory.removeAll()
        downHistory.removeAll()
        upHistory.removeAll()
        publish("live.cpu-history", .list([]))
        publish("live.gpu-history", .list([]))
        publish("live.net-history", .list([]))
    }

    private func sampleBar() {
        guard isRunning, !bar.busy else { return }
        bar.busy = true
        let generation = bar.generation
        source.sample(PerfSampleRequest(gpu: false, disk: false)) { [weak self] sample in
            guard let self, self.isRunning, generation == self.bar.generation else { return }
            self.bar.busy = false
            self.ingestBar(sample)
        }
    }

    private func sampleLive() {
        guard isRunning, !live.busy else { return }
        live.busy = true
        let generation = live.generation
        source.sample(PerfSampleRequest(gpu: true, disk: true)) { [weak self] sample in
            guard let self, self.isRunning, generation == self.live.generation else { return }
            self.live.busy = false
            self.ingestLive(sample)
        }
    }

    private func ingestBar(_ sample: PerfSample) {
        if let cpu = Self.cpu(&bar, sample) { publish("cpu", .number(cpu)) }
        if let memory = sample.memory { publish("memory", .number(memory.fraction)) }
        if let counters = sample.network {
            bar.meter.add(counters, at: sample.time)
            publish("net-down", ProviderValue.number(bar.meter.rate?.download))
            publish("net-up", ProviderValue.number(bar.meter.rate?.upload))
        }
    }

    private func ingestLive(_ sample: PerfSample) {
        if let cpu = Self.cpu(&live, sample) {
            cpuHistory.append(cpu)
            publish("live.cpu", .number(cpu))
            publish("live.cpu-history", .list(cpuHistory.values.map(Value.number)))
        }
        publish("live.gpu", ProviderValue.number(sample.gpu))
        if let gpu = sample.gpu {
            gpuHistory.append(gpu)
            publish("live.gpu-history", .list(gpuHistory.values.map(Value.number)))
        }
        if let memory = sample.memory {
            publish("live.memory-used", .number(Double(memory.used)))
            publish("live.memory-total", .number(Double(memory.total)))
            publish("live.memory", .number(memory.fraction))
        }
        if let disk = sample.disk {
            publish("live.disk-used", .number(Double(disk.used)))
            publish("live.disk-total", .number(Double(disk.total)))
            publish("live.disk", .number(disk.fraction))
        }
        if let counters = sample.network {
            live.meter.add(counters, at: sample.time)
            let rate = live.meter.rate
            publish("live.net-down", ProviderValue.number(rate?.download))
            publish("live.net-up", ProviderValue.number(rate?.upload))
            if let rate {
                downHistory.append(rate.download)
                upHistory.append(rate.upload)
                publish("live.net-history", .list(zip(downHistory.values, upHistory.values).map { down, up in
                    .record(Record([("down", .number(down)), ("up", .number(up))]))
                }))
            }
            publish("live.net-total-down", .number(Double(live.meter.total.received)))
            publish("live.net-total-up", .number(Double(live.meter.total.sent)))
        }
    }

    private static func cpu(_ tier: inout Tier, _ sample: PerfSample) -> Double? {
        guard let ticks = sample.cpuTicks else { return nil }
        defer { tier.lastTicks = ticks }
        guard let old = tier.lastTicks else { return nil }
        return ResourceMath.cpuUsage(from: old, to: ticks)
    }
}
