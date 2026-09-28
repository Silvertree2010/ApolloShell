#if canImport(Glibc)
import Glibc

let SOCK_STREAM = Int32(Glibc.SOCK_STREAM.rawValue)

enum Darwin {
    @discardableResult
    static func close(_ fd: Int32) -> Int32 { Glibc.close(fd) }
    static func connect(_ fd: Int32, _ address: UnsafePointer<sockaddr>, _ length: socklen_t) -> Int32 { Glibc.connect(fd, address, length) }
    static func bind(_ fd: Int32, _ address: UnsafePointer<sockaddr>, _ length: socklen_t) -> Int32 { Glibc.bind(fd, address, length) }
    static func write(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int { Glibc.write(fd, buffer, count) }
}
#endif
