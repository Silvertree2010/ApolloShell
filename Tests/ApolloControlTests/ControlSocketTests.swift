import Testing
import Foundation
import ApolloConfig
@testable import ApolloControl

@Suite("Socket-Server und Client", .serialized)
struct ControlSocketTests {
    @Test("Anfrage und Antwort gehen über den Socket")
    func roundTrip() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let server = ControlSocketServer(path: folder.socketPath, service: EchoService(probe: StreamProbe()))
        try server.start()
        defer { server.stop() }
        let client = try ControlSocketClient.connect(path: folder.socketPath)
        defer { client.close() }
        try client.send(ControlRequest(id: 1, cmd: "echo", args: Record([("x", .number(1))])))
        #expect(try client.readResponse() == ControlResponse(id: 1, outcome: .success(.record(Record([("x", .number(1))])))))
        try client.send(ControlRequest(id: 2, cmd: "fail", args: Record()))
        #expect(try client.readResponse() == ControlResponse(id: 2, outcome: .failure("it failed")))
        try client.send(ControlRequest(id: 3, cmd: "nan", args: Record()))
        #expect(try client.readResponse() == ControlResponse(id: 3, outcome: .success(.list([.null, .null, .number(1.5)]))))
    }

    @Test("kaputte Zeile bekommt eine Fehlerantwort, die Verbindung bleibt")
    func brokenLine() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let server = ControlSocketServer(path: folder.socketPath, service: EchoService(probe: StreamProbe()))
        try server.start()
        defer { server.stop() }
        let client = try ControlSocketClient.connect(path: folder.socketPath)
        defer { client.close() }
        try client.sendRaw("hello\n")
        let response = try #require(try client.readResponse())
        #expect(response.id == nil)
        if case .failure = response.outcome {} else { Issue.record("expected failure") }
        try client.send(ControlRequest(id: 9, cmd: "echo", args: Record()))
        #expect(try client.readResponse()?.id == 9)
    }

    @Test("Socket hat Rechte 0600")
    func permissions() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let server = ControlSocketServer(path: folder.socketPath, service: EchoService(probe: StreamProbe()))
        try server.start()
        defer { server.stop() }
        var info = stat()
        #expect(lstat(folder.socketPath, &info) == 0)
        #expect(info.st_mode & S_IFMT == S_IFSOCK)
        #expect(info.st_mode & 0o777 == 0o600)
    }

    @Test("fehlender Ordner wird mit 0700 angelegt")
    func createsFolder() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let path = folder.url.appendingPathComponent("d/s").path
        let server = ControlSocketServer(path: path, service: EchoService(probe: StreamProbe()))
        try server.start()
        defer { server.stop() }
        var info = stat()
        #expect(stat(folder.url.appendingPathComponent("d").path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o700)
    }

    @Test("ein veralteter Socket wird ersetzt")
    func replacesStaleSocket() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let stale = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = try SocketAddress.make(folder.socketPath)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(stale, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        #expect(bound == 0)
        close(stale)
        let server = ControlSocketServer(path: folder.socketPath, service: EchoService(probe: StreamProbe()))
        try server.start()
        defer { server.stop() }
        let client = try ControlSocketClient.connect(path: folder.socketPath)
        defer { client.close() }
        try client.send(ControlRequest(id: 1, cmd: "echo", args: Record()))
        #expect(try client.readResponse()?.id == 1)
    }

    @Test("ein laufender Socket wird nicht angetastet")
    func keepsRunningSocket() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let first = ControlSocketServer(path: folder.socketPath, service: EchoService(probe: StreamProbe()))
        try first.start()
        defer { first.stop() }
        let second = ControlSocketServer(path: folder.socketPath, service: EchoService(probe: StreamProbe()))
        #expect(throws: ControlSocketError.alreadyRunning(folder.socketPath)) { try second.start() }
        let client = try ControlSocketClient.connect(path: folder.socketPath)
        defer { client.close() }
        try client.send(ControlRequest(id: 5, cmd: "echo", args: Record()))
        #expect(try client.readResponse()?.id == 5)
    }

    @Test("eine gewöhnliche Datei am Pfad bleibt stehen")
    func keepsRegularFile() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        try "keep".write(toFile: folder.socketPath, atomically: true, encoding: .utf8)
        let server = ControlSocketServer(path: folder.socketPath, service: EchoService(probe: StreamProbe()))
        #expect(throws: ControlSocketError.occupied(folder.socketPath)) { try server.start() }
        #expect(try String(contentsOfFile: folder.socketPath, encoding: .utf8) == "keep")
    }

    @Test("zu langer Pfad ist ein klarer Fehler")
    func pathTooLong() {
        let path = "/tmp/" + String(repeating: "x", count: 120)
        let server = ControlSocketServer(path: path, service: EchoService(probe: StreamProbe()))
        #expect(throws: ControlSocketError.pathTooLong(path)) { try server.start() }
    }

    @Test("stop entfernt den Socket")
    func stopRemovesSocket() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let server = ControlSocketServer(path: folder.socketPath, service: EchoService(probe: StreamProbe()))
        try server.start()
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: folder.socketPath))
        #expect(throws: ControlSocketError.notRunning(folder.socketPath)) { _ = try ControlSocketClient.connect(path: folder.socketPath) }
    }

    @Test("watch liefert bei drei Änderungen drei Zeilen, Trennen meldet ab")
    func watchStream() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let probe = StreamProbe()
        let server = ControlSocketServer(path: folder.socketPath, service: EchoService(probe: probe))
        try server.start()
        defer { server.stop() }
        let client = try ControlSocketClient.connect(path: folder.socketPath)
        try client.send(ControlRequest(id: 11, cmd: "watch", args: Record()))
        #expect(waitUntil { probe.hasSubscriber })
        for value in [1.0, 2.0, 3.0] {
            probe.yield(.number(value))
        }
        var results: [ControlResponse] = []
        for _ in 0..<3 {
            if let response = try client.readResponse() { results.append(response) }
        }
        #expect(results == [1.0, 2.0, 3.0].map { ControlResponse(id: 11, outcome: .success(.number($0))) })
        client.close()
        #expect(waitUntil { probe.wasTerminated })
    }

    @Test("Schliesst der Client nach der Anfrage seine Schreibseite, kommt die Antwort trotzdem, danach trennt der Server")
    func halfClose() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let server = ControlSocketServer(path: folder.socketPath, service: EchoService(probe: StreamProbe()))
        try server.start()
        defer { server.stop() }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        #expect(try SocketAddress.connect(fd, folder.socketPath) == 0)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        #expect(SocketAddress.writeAll(fd, ControlRequest(id: 4, cmd: "slow").line + "\n"))
        #expect(shutdown(fd, SHUT_WR) == 0)
        var buffer = LineBuffer()
        var lines: [String] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        var sawEnd = false
        while !sawEnd {
            let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count <= 0 {
                sawEnd = count == 0
                break
            }
            lines += buffer.append(chunk[..<count])
        }
        #expect(lines.map(ControlResponse.parse) == [ControlResponse(id: 4, outcome: .success(.string("late")))])
        #expect(sawEnd)
    }

    @Test("Pfad kommt aus APOLLO_SOCKET, sonst aus Application Support")
    func socketPath() {
        let home = URL(fileURLWithPath: "/Users/x")
        #expect(ControlSocketPath.resolve(environment: ["APOLLO_SOCKET": "/tmp/a.sock"], home: home) == "/tmp/a.sock")
        #expect(ControlSocketPath.resolve(environment: ["APOLLO_SOCKET": ""], home: home) == "/Users/x/Library/Application Support/ApolloShell/apollo.sock")
        #expect(ControlSocketPath.resolve(environment: [:], home: home) == "/Users/x/Library/Application Support/ApolloShell/apollo.sock")
    }
}
