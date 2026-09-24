import Foundation
import ApolloRuntime
@testable import ApolloProviders

@MainActor
final class FakeScriptHandle: ScriptHandle {
    var terminated = false
    let completion: (@MainActor (Int32, String) -> Void)?
    let onLine: (@MainActor (String) -> Void)?
    let onExit: (@MainActor (Int32) -> Void)?

    init(completion: (@MainActor (Int32, String) -> Void)? = nil, onLine: (@MainActor (String) -> Void)? = nil, onExit: (@MainActor (Int32) -> Void)? = nil) {
        self.completion = completion
        self.onLine = onLine
        self.onExit = onExit
    }

    func terminate() {
        terminated = true
    }
}

@MainActor
final class FakeScriptRunner: ScriptRunner {
    let clock: ManualRuntimeClock
    var output = "connected\n"
    var status: Int32 = 0
    var answersImmediately = true
    var runs: [String] = []
    var handles: [FakeScriptHandle] = []

    init(clock: ManualRuntimeClock) {
        self.clock = clock
    }

    var now: Date { Date(timeIntervalSince1970: clock.now) }

    func run(_ command: String, _ completion: @escaping @MainActor (Int32, String) -> Void) -> (any ScriptHandle)? {
        runs.append(command)
        let handle = FakeScriptHandle(completion: completion)
        handles.append(handle)
        if answersImmediately { completion(status, output) }
        return handle
    }

    func stream(_ command: String, onLine: @escaping @MainActor (String) -> Void, onExit: @escaping @MainActor (Int32) -> Void) -> (any ScriptHandle)? {
        runs.append(command)
        let handle = FakeScriptHandle(onLine: onLine, onExit: onExit)
        handles.append(handle)
        return handle
    }

    var last: FakeScriptHandle { handles[handles.count - 1] }
}
