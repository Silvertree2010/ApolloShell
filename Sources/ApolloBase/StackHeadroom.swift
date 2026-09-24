import Foundation

public enum StackHeadroom {
    public static func run<Value: Sendable>(
        minimum: Int = 1 << 20,
        stackSize: Int = 8 << 20,
        _ body: @escaping @Sendable () -> Value
    ) -> Value {
        guard availableBytes() < minimum else { return body() }
        return runOnDedicatedThread(stackSize: stackSize, body)
    }

    static func availableBytes() -> Int {
        let thread = pthread_self()
        let base = UInt(bitPattern: pthread_get_stackaddr_np(thread))
        let size = UInt(pthread_get_stacksize_np(thread))
        let bottom = base - size
        var marker: UInt8 = 0
        let current = withUnsafePointer(to: &marker) { UInt(bitPattern: $0) }
        guard current > bottom else { return 0 }
        return Int(current - bottom)
    }

    private static func runOnDedicatedThread<Value: Sendable>(
        stackSize: Int,
        _ body: @escaping @Sendable () -> Value
    ) -> Value {
        let box = StackHeadroomResultBox<Value>()
        let semaphore = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.value = body()
            semaphore.signal()
        }
        thread.stackSize = stackSize
        thread.qualityOfService = Thread.current.qualityOfService
        thread.start()
        semaphore.wait()
        return box.value!
    }
}

private final class StackHeadroomResultBox<Value>: @unchecked Sendable {
    var value: Value?
}
