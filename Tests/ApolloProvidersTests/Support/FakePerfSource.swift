import ApolloRuntime
import ApolloShellCore
@testable import ApolloProviders

@MainActor
final class FakePerfSource: PerfSource {
    let clock: ManualRuntimeClock
    let chip = "Apple M4 Pro"
    let cores = 14
    let gpuCores: Int? = 20
    var requests: [PerfSampleRequest] = []

    init(clock: ManualRuntimeClock) {
        self.clock = clock
    }

    func sample(_ request: PerfSampleRequest, _ completion: @escaping @MainActor (PerfSample) -> Void) {
        requests.append(request)
        let now = clock.now
        let ticks = CPUTicks(user: UInt64(now * 4200), system: 0, idle: UInt64(now * 5800), nice: 0)
        let counters = NetCounters(received: UInt64(now * 2000), sent: UInt64(now * 1000))
        completion(PerfSample(
            time: now,
            cpuTicks: ticks,
            gpu: request.gpu ? 0.25 : nil,
            memory: ByteUsage(used: 61, total: 100),
            disk: request.disk ? ByteUsage(used: 500, total: 1000) : nil,
            network: counters
        ))
    }
}
