import Foundation
import ApolloProviders
import ApolloShellCore

@MainActor
final class SystemPerfSource: PerfSource {
    private let queue = DispatchQueue(label: AppIdentity.scoped("perf"), qos: .utility)

    var chip: String { PerformanceSampler.chipName }

    var cores: Int { ProcessInfo.processInfo.activeProcessorCount }

    var gpuCores: Int? { PerformanceSampler.gpuCores }

    func sample(_ request: PerfSampleRequest, _ completion: @escaping @MainActor (PerfSample) -> Void) {
        queue.async {
            let sample = PerfSample(
                time: ProcessInfo.processInfo.systemUptime,
                cpuTicks: SystemSampler.cpuTicks(),
                gpu: request.gpu ? PerformanceSampler.gpuUsage() : nil,
                memory: SystemSampler.memory().map { ByteUsage(used: $0.used, total: $0.total) },
                disk: request.disk ? SystemSampler.storage().map { ByteUsage(used: $0.used, total: $0.total) } : nil,
                network: PerformanceSampler.networkCounters()
            )
            Task { @MainActor in completion(sample) }
        }
    }
}
