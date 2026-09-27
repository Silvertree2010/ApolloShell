struct KDLSource: Sendable {
    struct Decoded {
        let scalar: Unicode.Scalar
        let length: Int
    }

    let bytes: [UInt8]

    init(_ text: String) {
        bytes = Array(text.utf8)
    }

    var count: Int {
        bytes.count
    }

    var bomLength: Int {
        bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
    }

    func byte(at offset: Int) -> UInt8? {
        offset >= 0 && offset < bytes.count ? bytes[offset] : nil
    }

    func decoded(at offset: Int) -> Decoded? {
        guard offset >= 0, offset < bytes.count else { return nil }
        let lead = bytes[offset]
        if lead < 0x80 {
            return Decoded(scalar: Unicode.Scalar(lead), length: 1)
        }
        let length: Int
        var value: UInt32
        if lead >= 0xF0 {
            length = 4
            value = UInt32(lead & 0x07)
        } else if lead >= 0xE0 {
            length = 3
            value = UInt32(lead & 0x0F)
        } else {
            length = 2
            value = UInt32(lead & 0x1F)
        }
        for step in 1..<length where offset + step < bytes.count {
            value = (value << 6) | UInt32(bytes[offset + step] & 0x3F)
        }
        return Decoded(scalar: Unicode.Scalar(value) ?? "\u{FFFD}", length: length)
    }

    func hasPrefix(_ literal: String, at offset: Int) -> Bool {
        guard offset >= 0 else { return false }
        var index = offset
        for byte in literal.utf8 {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
        }
        return true
    }

    func string(from start: Int, to end: Int) -> String {
        String(decoding: bytes[start..<end], as: UTF8.self)
    }

    func newlineLength(at offset: Int) -> Int? {
        guard let decoded = decoded(at: offset), KDLCharacters.isNewline(decoded.scalar) else { return nil }
        if decoded.scalar == "\r", byte(at: offset + 1) == 0x0A {
            return 2
        }
        return decoded.length
    }

    func lineStart(before offset: Int) -> Int {
        var index = offset - 1
        while index >= bomLength {
            let current = bytes[index]
            if current == 0x0A || current == 0x0D || current == 0x0C {
                return index + 1
            }
            if current == 0x85, index >= 1, bytes[index - 1] == 0xC2 {
                return index + 1
            }
            if current == 0xA8 || current == 0xA9, index >= 2, bytes[index - 1] == 0x80, bytes[index - 2] == 0xE2 {
                return index + 1
            }
            index -= 1
        }
        return bomLength
    }
}
