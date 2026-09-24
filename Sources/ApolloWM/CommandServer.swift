import Darwin
import Foundation

@MainActor
public final class CommandServer {
    public let path: String
    private let handler: @MainActor (String) -> String
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?

    public var log: (String) -> Void = { print($0) }

    public init(path: String, handler: @escaping @MainActor (String) -> String) {
        self.path = path
        self.handler = handler
    }

    @discardableResult
    public func start() -> Bool {
        stop()
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            close(fd)
            log("command socket path too long: \(path)")
            return false
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: path.utf8)
            raw[path.utf8.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            log("command socket failed: \(String(cString: strerror(errno)))")
            close(fd)
            return false
        }
        descriptor = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.accept() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        return true
    }

    public func stop() {
        source?.cancel()
        source = nil
        if descriptor >= 0 { unlink(path) }
        descriptor = -1
    }

    private func accept() {
        let client = Darwin.accept(descriptor, nil, nil)
        guard client >= 0 else { return }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let line = Self.readLine(client)
            DispatchQueue.main.async {
                let reply = MainActor.assumeIsolated { self?.handler(line) } ?? "error: stopped"
                DispatchQueue.global(qos: .userInitiated).async {
                    let bytes = Array((reply + "\n").utf8)
                    var sent = 0
                    while sent < bytes.count {
                        let count = bytes[sent...].withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
                        guard count > 0 else { break }
                        sent += count
                    }
                    close(client)
                }
            }
        }
    }

    private nonisolated static func readLine(_ fd: Int32) -> String {
        var data = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 512)
        while data.count < 4096 {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { break }
            data += buffer[0..<count]
            if data.contains(UInt8(ascii: "\n")) { break }
        }
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}
