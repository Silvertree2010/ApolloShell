import Foundation
import ApolloShellCore

public struct ByteUsage: Equatable, Sendable {
    public var used: UInt64
    public var total: UInt64

    public init(used: UInt64, total: UInt64) {
        self.used = used
        self.total = total
    }

    public var fraction: Double { ResourceMath.fraction(used: used, total: total) }
}

public struct PerfSample: Equatable, Sendable {
    public var time: TimeInterval
    public var cpuTicks: CPUTicks?
    public var gpu: Double?
    public var memory: ByteUsage?
    public var disk: ByteUsage?
    public var network: NetCounters?

    public init(time: TimeInterval, cpuTicks: CPUTicks?, gpu: Double? = nil, memory: ByteUsage? = nil, disk: ByteUsage? = nil, network: NetCounters? = nil) {
        self.time = time
        self.cpuTicks = cpuTicks
        self.gpu = gpu
        self.memory = memory
        self.disk = disk
        self.network = network
    }
}

public struct PerfSampleRequest: Equatable, Sendable {
    public var gpu: Bool
    public var disk: Bool

    public init(gpu: Bool, disk: Bool) {
        self.gpu = gpu
        self.disk = disk
    }
}

@MainActor
public protocol PerfSource: AnyObject {
    var chip: String { get }
    var cores: Int { get }
    var gpuCores: Int? { get }
    func sample(_ request: PerfSampleRequest, _ completion: @escaping @MainActor (PerfSample) -> Void)
}
