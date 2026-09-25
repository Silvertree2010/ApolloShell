import Testing
import Foundation
@testable import ApolloShell

@MainActor
@Suite("Skript-Prozesse beim Abbrechen", .serialized)
struct ScriptRunnerTests {
    @Test("Abbrechen beendet auch die Kindprozesse einer Pipeline")
    func terminateKillsPipeline() async throws {
        let runner = SystemScriptRunner(socketPath: nil)
        let handle = try #require(runner.stream("sleep 41 | sleep 42", onLine: { _ in }, onExit: { _ in }) as? SystemScriptHandle)
        var children: [pid_t] = []
        for _ in 0..<100 where children.count < 2 {
            children = ProcessTree.descendants(of: handle.process.processIdentifier)
            RunLoopPump.run(0.02)
        }
        #expect(children.count >= 2)
        handle.terminate()
        for _ in 0..<100 where children.contains(where: { kill($0, 0) == 0 }) { RunLoopPump.run(0.02) }
        #expect(!children.contains { kill($0, 0) == 0 })
    }
}
