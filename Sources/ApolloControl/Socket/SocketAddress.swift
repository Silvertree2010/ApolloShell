import Foundation

public enum ControlSocketError: Error, Sendable, Hashable, CustomStringConvertible {
    case pathTooLong(String)
    case alreadyRunning(String)
    case occupied(String)
    case notRunning(String)
    case system(String, Int32)
    case closed

    public var description: String {
        switch self {
        case .pathTooLong(let path): "socket path is too long: \(path)"
        case .alreadyRunning(let path): "another ApolloShell already listens on \(path)"
        case .occupied(let path): "\(path) exists and is not a socket"
        case .notRunning(let path): "ApolloShell is not running (no socket at \(path))"
        case .system(let call, let code): "\(call) failed: \(String(cString: strerror(code)))"
        case .closed: "the connection was closed"
        }
    }
}

enum SocketAddress {
    static func make(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard !bytes.isEmpty, bytes.count < capacity else { throw ControlSocketError.pathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        #if canImport(Darwin)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        return address
    }

    static func connect(_ fd: Int32, _ path: String) throws -> Int32 {
        var address = try make(path)
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    static func bind(_ fd: Int32, _ path: String) throws -> Int32 {
        var address = try make(path)
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    static func noSigPipe(_ fd: Int32) {
        #if canImport(Darwin)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    static func sendTimeout(_ fd: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    static func writeAll(_ fd: Int32, _ text: String) -> Bool {
        let bytes = Array(text.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { buffer in
                Darwin.write(fd, buffer.baseAddress! + offset, bytes.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                return false
            }
            offset += written
        }
        return true
    }
}

struct LineBuffer {
    private var pending: [UInt8] = []

    mutating func append(_ bytes: ArraySlice<UInt8>) -> [String] {
        pending.append(contentsOf: bytes)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 10) {
            let line = String(decoding: pending[..<newline], as: UTF8.self)
            pending.removeSubrange(...newline)
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(line)
            }
        }
        return lines
    }
}
