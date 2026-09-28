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

    @Test("Zeilenpuffer wächst ohne Zeilenumbruch nicht über 1 MiB")
    func lineBufferLimit() {
        let buffer = LineBuffer()
        #expect(buffer.append(Data("a\nb".utf8)) == ["a"])
        let lines = buffer.append(Data(repeating: 0x41, count: LineBuffer.limit + 10))
        #expect(lines.count == 1)
        #expect(lines.first?.count == LineBuffer.limit + 11)
        #expect(buffer.append(Data("c\n".utf8)) == ["c"])
    }

    @Test("die letzte Zeile ohne Zeilenumbruch kommt an, das Ende erst nach allen Zeilen")
    func lastLineBeforeExit() async throws {
        let runner = SystemScriptRunner(socketPath: nil)
        var events: [String] = []
        _ = runner.stream("printf 'a\\nb'", onLine: { events.append($0) }, onExit: { events.append("exit \($0)") })
        for _ in 0..<500 where events.count < 3 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(events == ["a", "b", "exit 0"])
    }

    @Test("das Ende kommt auch, wenn ein Hintergrundprozess die Ausgabe offen hält")
    func exitWithOpenOutput() async throws {
        let runner = SystemScriptRunner(socketPath: nil)
        var status: Int32?
        _ = runner.stream("sleep 3 & echo x", onLine: { _ in }, onExit: { status = $0 })
        for _ in 0..<250 where status == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(status == 0)
    }

    @Test("einmalige Skripte behalten höchstens 1 MiB Ausgabe und laufen trotzdem zu Ende")
    func runOutputLimit() async throws {
        let runner = SystemScriptRunner(socketPath: nil)
        var result: (Int32, Int)?
        _ = runner.run("head -c 3000000 /dev/zero; echo done", { status, text in result = (status, text.utf8.count) })
        for _ in 0..<1000 where result == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(result?.0 == 0)
        #expect(result?.1 == ScriptOutput.limit)
    }

    @Test("Zeilenpuffer gibt den Rest ohne Zeilenumbruch am Ende heraus")
    func lineBufferFinish() {
        let buffer = LineBuffer()
        #expect(buffer.append(Data("a\nb".utf8)) == ["a"])
        #expect(buffer.finish() == ["b"])
        #expect(buffer.finish().isEmpty)
    }
}
