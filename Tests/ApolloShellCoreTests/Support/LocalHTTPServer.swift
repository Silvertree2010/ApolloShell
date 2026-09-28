#if canImport(Network)
import Foundation
import Network

struct HTTPExchange: Sendable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    var json: [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}

struct HTTPAnswer: Sendable {
    var status: Int
    var body: String

    init(_ status: Int = 200, _ body: String = "") {
        self.status = status
        self.body = body
    }
}

final class LocalHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "local-http-server")
    private let lock = NSLock()
    private var log: [HTTPExchange] = []
    private let route: @Sendable (HTTPExchange) -> HTTPAnswer

    init(route: @escaping @Sendable (HTTPExchange) -> HTTPAnswer) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        self.route = route
    }

    var exchanges: [HTTPExchange] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    func start() async throws -> URL {
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    once.run { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error):
                    once.run { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
        }
        return URL(string: "http://127.0.0.1:\(port)")!
    }

    func stop() {
        listener.cancel()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let exchange = Self.parse(buffer) {
                self.answer(exchange, on: connection)
            } else if complete || error != nil {
                connection.cancel()
            } else {
                self.read(connection, buffer: buffer)
            }
        }
    }

    private func answer(_ exchange: HTTPExchange, on connection: NWConnection) {
        lock.lock()
        log.append(exchange)
        lock.unlock()
        let answer = route(exchange)
        let body = Data(answer.body.utf8)
        var head = "HTTP/1.1 \(answer.status) X\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if !body.isEmpty { head += "Content-Type: application/json\r\n" }
        head += "\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    static func parse(_ buffer: Data) -> HTTPExchange? {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: buffer[..<end.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = buffer[end.upperBound...]
        guard body.count >= length else { return nil }
        return HTTPExchange(method: String(first[0]), path: String(first[1]), headers: headers, body: Data(body.prefix(length)))
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ work: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        work()
    }
}
#endif
