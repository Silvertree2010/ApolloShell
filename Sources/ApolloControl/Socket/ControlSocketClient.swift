import Foundation

public final class ControlSocketClient {
    private let fd: Int32
    private var buffer = LineBuffer()
    private var ready: [String] = []
    private var isClosed = false

    private init(fd: Int32) {
        self.fd = fd
    }

    public static func connect(path: String) throws -> ControlSocketClient {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlSocketError.system("socket", errno) }
        do {
            guard try SocketAddress.connect(fd, path) == 0 else {
                let code = errno
                Darwin.close(fd)
                if code == ENOENT || code == ECONNREFUSED || code == ENOTDIR {
                    throw ControlSocketError.notRunning(path)
                }
                throw ControlSocketError.system("connect", code)
            }
        } catch {
            if case ControlSocketError.pathTooLong = error { Darwin.close(fd) }
            throw error
        }
        SocketAddress.noSigPipe(fd)
        return ControlSocketClient(fd: fd)
    }

    public func send(_ request: ControlRequest) throws {
        try sendRaw(request.line + "\n")
    }

    public func sendRaw(_ text: String) throws {
        guard !isClosed, SocketAddress.writeAll(fd, text) else { throw ControlSocketError.closed }
    }

    public func readResponse() throws -> ControlResponse? {
        while true {
            if !ready.isEmpty {
                let line = ready.removeFirst()
                guard let response = ControlResponse.parse(line) else {
                    throw ControlSocketError.system("parse", EBADMSG)
                }
                return response
            }
            guard !isClosed else { return nil }
            var chunk = [UInt8](repeating: 0, count: 65_536)
            let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw ControlSocketError.system("read", errno)
            }
            if count == 0 { return nil }
            ready.append(contentsOf: buffer.append(chunk[..<count]))
            if buffer.overflowed { throw ControlSocketError.system("read", EMSGSIZE) }
        }
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        Darwin.close(fd)
    }

    deinit {
        close()
    }
}
