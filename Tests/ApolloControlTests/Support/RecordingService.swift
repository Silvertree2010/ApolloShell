import Foundation
import ApolloConfig
@testable import ApolloControl

final class StreamProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Value>.Continuation?
    private var terminated = false

    func makeStream() -> AsyncStream<Value> {
        AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { self.terminated = true }
            }
            self.lock.withLock { self.continuation = continuation }
        }
    }

    func yield(_ value: Value) {
        _ = lock.withLock { continuation }?.yield(value)
    }

    var hasSubscriber: Bool { lock.withLock { continuation != nil } }

    var wasTerminated: Bool { lock.withLock { terminated } }
}

struct EchoService: ControlService {
    let probe: StreamProbe

    func reply(to request: ControlRequest) async -> ControlReply {
        switch request.cmd {
        case "echo":
            return .success(.record(request.args))
        case "fail":
            return .failure("it failed")
        case "nan":
            return .success(.list([.number(.nan), .number(.infinity), .number(1.5)]))
        case "watch":
            return .stream(probe.makeStream())
        default:
            return .failure("unknown command '\(request.cmd)'")
        }
    }
}

func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        usleep(5_000)
    }
    return condition()
}
