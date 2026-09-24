import Foundation

/// The major macOS SDK version an executable was built against.
///
/// macOS 26 gives an app's windows the new, rounder corners only when the
/// app was built with the 26 SDK; older builds (kitty with SDK 15.2, say)
/// keep the old 10 pt corners. The TWM's border has to match either.
public enum MachOSDK {
    /// Nil when the data is no Mach-O executable or names no SDK.
    public static func major(of data: Data) -> Int? {
        guard let magic = data.word(at: 0, bigEndian: true) else { return nil }
        if magic == 0xCAFE_BABE { return fatMajor(data) }
        return thinMajor(data)
    }

    /// Reads an executable from disk. Only the start is read: the header and
    /// load commands; for a universal binary, the slice's start too.
    public static func major(ofExecutableAt url: URL) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 64 * 1024) else { return nil }
        if head.word(at: 0, bigEndian: true) == 0xCAFE_BABE, let slice = armSlice(head) {
            guard (try? handle.seek(toOffset: UInt64(slice))) != nil,
                  let body = try? handle.read(upToCount: 64 * 1024) else { return nil }
            return thinMajor(body)
        }
        return major(of: head)
    }

    private static let arm64: UInt32 = 0x0100_000C

    /// Offset of the arm64 slice (the first slice when there is none).
    private static func armSlice(_ data: Data) -> Int? {
        guard let count = data.word(at: 4, bigEndian: true), count > 0, count < 16 else { return nil }
        var first: Int?
        for index in 0..<Int(count) {
            let base = 8 + index * 20
            guard let type = data.word(at: base, bigEndian: true),
                  let offset = data.word(at: base + 8, bigEndian: true) else { return nil }
            if type == arm64 { return Int(offset) }
            first = first ?? Int(offset)
        }
        return first
    }

    private static func fatMajor(_ data: Data) -> Int? {
        guard let offset = armSlice(data), offset < data.count else { return nil }
        return thinMajor(data.subdata(in: offset..<data.count))
    }

    private static func thinMajor(_ data: Data) -> Int? {
        guard data.word(at: 0) == 0xFEED_FACF, let count = data.word(at: 16) else { return nil }
        var cursor = 32
        for _ in 0..<count {
            guard let command = data.word(at: cursor), let size = data.word(at: cursor + 4), size >= 8 else { return nil }
            switch command {
            case 0x32: // LC_BUILD_VERSION: platform, minos, sdk
                return data.word(at: cursor + 16).map { Int($0 >> 16) }
            case 0x24: // LC_VERSION_MIN_MACOSX: version, sdk
                return data.word(at: cursor + 12).map { Int($0 >> 16) }
            default:
                cursor += Int(size)
            }
        }
        return nil
    }
}

private extension Data {
    func word(at offset: Int, bigEndian: Bool = false) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let start = index(startIndex, offsetBy: offset)
        let value = self[start..<index(start, offsetBy: 4)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return bigEndian ? value : value.byteSwapped
    }
}
