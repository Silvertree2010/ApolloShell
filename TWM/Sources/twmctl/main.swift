import Darwin
import Foundation

// twmctl: sends one command to ApolloShell's tiling window manager and
// prints the reply, like Hyprland's hyprctl.
//
//   twmctl focus left
//   twmctl send 3
//   twmctl windows
//
// The socket lives in ApolloShell's folder; APOLLOSHELL_TWM_SOCKET overrides it.

let arguments = CommandLine.arguments.dropFirst()
guard !arguments.isEmpty, arguments.first != "-h", arguments.first != "--help" else {
    print("""
    usage: twmctl COMMAND
      focus left|right|up|down|next   swap left|right|up|down
      split   equalize   grow W H   group   tab next|prev   float   fullscreen
      close   terminal   desktop N   send N   scratchpad
      windows (JSON)   ping
    """)
    exit(arguments.isEmpty ? 1 : 0)
}

let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
let path = ProcessInfo.processInfo.environment["APOLLOSHELL_TWM_SOCKET"]
    ?? support.appendingPathComponent("ApolloShell/twm.sock").path

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &address.sun_path) { raw in
    let bytes = Array(path.utf8.prefix(raw.count - 1))
    raw.copyBytes(from: bytes)
    raw[bytes.count] = 0
}
let connected = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connected == 0 else {
    FileHandle.standardError.write(Data("twmctl: the TWM is not running (no socket at \(path))\n".utf8))
    exit(1)
}
let line = Array((arguments.joined(separator: " ") + "\n").utf8)
_ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
var reply = [UInt8]()
var buffer = [UInt8](repeating: 0, count: 4096)
while true {
    let count = read(fd, &buffer, buffer.count)
    guard count > 0 else { break }
    reply += buffer[0..<count]
}
close(fd)
let text = String(decoding: reply, as: UTF8.self)
print(text, terminator: "")
exit(text.hasPrefix("error") ? 1 : 0)
