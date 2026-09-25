import Testing
import Foundation
@testable import ApolloShell

@MainActor
@Suite("Runloop-Observer misst Blockaden, nicht den Leerlauf (V7)")
struct MainBlockObserverTests {
    @Test("60 ms Arbeit und danach Warten ergibt etwa 60 ms, nicht die ganze Zeit")
    func measuresBlockNotIdle() {
        let observer = MainBlockObserver.shared
        _ = observer.takeLongest()
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) { usleep(60_000) }
        CFRunLoopWakeUp(CFRunLoopGetMain())
        CFRunLoopRunInMode(.defaultMode, 0.25, false)
        CFRunLoopRunInMode(.defaultMode, 0.25, false)
        let longest = observer.takeLongest()
        #expect(longest >= 60)
        #expect(longest < 200)
    }
}
